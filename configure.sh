#!/bin/sh

prog_NAME="$(basename "$0")"

err()
{
    echo "${prog_NAME}: ERROR: $*" 1>&2
}

die()
{
    echo "${prog_NAME}: ERROR: $*" 1>&2
    exit 1
}

usage()
{
    cat <<EOM 1>&2
usage: ${prog_NAME} [ OPTIONS ]
Configures the ocaml-solo5 build system.
Options:
    --prefix=DIR
        Installation prefix (default: /usr/local).
    --sysroot=DIR
        Installation prefix for the OCaml cross-compiler and its supporting
        libraries (default: <installation prefix>/lib/ocaml-solo5).
    --target=TARGET
        Solo5 compiler toolchain to use.
    --othertoolprefix=PREFIX
        Prefix for tools besides the Solo5 toolchain
        (default: \`TARGET-cc -dumpmachine\`-).
    --ocaml-configure-option=OPTION
        Add an option to the OCaml compiler configuration.
EOM
    exit 1
}

OCAML_CONFIGURE_OPTIONS=
MAKECONF_PREFIX=/usr/local

while [ $# -gt 0 ]; do
    OPT="$1"

    case "${OPT}" in
        --target=*)
            CONFIG_TARGET="${OPT#*=}"
            ;;
        --othertoolprefix=*)
            MAKECONF_TOOLPREFIX="${OPT#*=}"
            ;;
        --prefix=*)
            MAKECONF_PREFIX="${OPT#*=}"
            ;;
        --sysroot=*)
            MAKECONF_SYSROOT="${OPT#*=}"
            ;;
        --ocaml-configure-option=*)
            OCAML_CONFIGURE_OPTIONS="${OCAML_CONFIGURE_OPTIONS} ${OPT#*=}"
            ;;
        --help)
            usage
            ;;
        *)
            err "Unknown option: '${OPT}'"
            usage
            ;;
    esac

    shift
done

MAKECONF_SYSROOT="${MAKECONF_SYSROOT:-$MAKECONF_PREFIX/lib/ocaml-solo5}"

[ -z "${CONFIG_TARGET}" ] && die "The --target option needs to be specified."

TARGET_TRIPLET="$("$CONFIG_TARGET-cc" -dumpmachine)"


case "${TARGET_TRIPLET}" in
    amd64-*|x86_64-*)
        TARGET_ARCH="x86_64"
        ;;
    aarch64-*)
        TARGET_ARCH="aarch64"
        ;;
    *)
        die "Unsupported build architecture: ${TARGET_TRIPLET}"
        ;;
esac

#
# macOS hosts have no ELF binutils and no libgcc for the target. Use LLVM's
# binutils (Homebrew's llvm is keg-only, so look in its prefix too) and take
# libgcc.a from a bare-metal GCC (e.g. Homebrew's aarch64-elf-gcc), which is
# copied into the sysroot so that the installed toolchain does not depend on
# where it came from.
#
MAKECONF_AR=
MAKECONF_LIBGCC=
if [ "$(uname -s)" = "Darwin" ]; then
    find_tool()
    {
        if command -v "$1" >/dev/null 2>&1; then
            command -v "$1"
            return 0
        fi
        for _dir in /opt/homebrew/opt/llvm/bin /opt/homebrew/bin \
            /usr/local/opt/llvm/bin /usr/local/bin /opt/local/bin; do
            if [ -x "${_dir}/$1" ]; then
                echo "${_dir}/$1"
                return 0
            fi
        done
        return 1
    }
    if [ -z "${MAKECONF_TOOLPREFIX}" ]; then
        LLVM_AR="$(find_tool llvm-ar)" || \
            die "llvm-ar not found: run 'brew install llvm'"
        MAKECONF_TOOLPREFIX="${LLVM_AR%ar}"
    fi
    MAKECONF_AR="${MAKECONF_TOOLPREFIX}ar"
    # The cross build compiles some tools with the host ocamlopt, passing
    # the target's -function-sections; a macOS (Mach-O) ocamlopt rejects it.
    OCAML_CONFIGURE_OPTIONS="${OCAML_CONFIGURE_OPTIONS} --disable-function-sections"
    if [ "${TARGET_ARCH}" = "aarch64" ]; then
        if [ -z "${LIBGCC}" ]; then
            ELF_GCC="$(find_tool aarch64-elf-gcc)" || \
                die "aarch64-elf-gcc not found. libgcc.a for aarch64 is" \
                    "required: run 'brew install aarch64-elf-gcc', or set" \
                    "LIBGCC to the path of a libgcc.a for aarch64."
            LIBGCC="$("${ELF_GCC}" -print-libgcc-file-name)"
        fi
        [ -f "${LIBGCC}" ] || die "libgcc.a not found at '${LIBGCC}'"
        MAKECONF_LIBGCC="${LIBGCC}"
    fi
fi

MAKECONF_TOOLPREFIX="${MAKECONF_TOOLPREFIX:-$TARGET_TRIPLET-}"

cat <<EOM >Makeconf
MAKECONF_AR=${MAKECONF_AR}
MAKECONF_LIBGCC=${MAKECONF_LIBGCC}
MAKECONF_PREFIX=${MAKECONF_PREFIX}
MAKECONF_SYSROOT=${MAKECONF_SYSROOT}
MAKECONF_TOOLCHAIN=${CONFIG_TARGET}
MAKECONF_TOOLPREFIX=${MAKECONF_TOOLPREFIX}
MAKECONF_TARGET_ARCH=${TARGET_ARCH}
MAKECONF_OCAML_CONFIGURE_OPTIONS=${OCAML_CONFIGURE_OPTIONS}
EOM
