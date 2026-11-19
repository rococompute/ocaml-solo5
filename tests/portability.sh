#!/bin/sh
# CC should be the Solo5 freestanding C compiler wrapper.
set -eu
root="$(cd "$(dirname "$0")/.." && pwd)"
CC="${CC:-aarch64-solo5-none-static-cc}"
work="$(mktemp -d "${TMPDIR:-/tmp}/ocaml-solo5-headers.XXXXXX")"
trap 'rm -rf "${work}"' EXIT
cat > "${work}/headers.c" <<'C'
#include <sys/types.h>
#include <time.h>
#include <sys/time.h>
#include <unistd.h>
#include <stdio.h>
#include <limits.h>
_Static_assert(CHAR_BIT == 8, "byte size");
_Static_assert(SCHAR_MIN == -128 && SCHAR_MAX == 127, "signed char");
_Static_assert(ULLONG_MAX == 18446744073709551615ULL, "unsigned long long");
_Static_assert(MB_LEN_MAX >= 1, "locale width");
#ifdef __CHAR_UNSIGNED__
_Static_assert(CHAR_MIN == 0 && CHAR_MAX == UCHAR_MAX, "unsigned char mode");
#else
_Static_assert(CHAR_MIN == SCHAR_MIN && CHAR_MAX == SCHAR_MAX, "signed char mode");
#endif
_Static_assert(SEEK_SET == 0 && SEEK_CUR == 1 && SEEK_END == 2, "seek constants");
struct timespec deadline;
time_t seconds;
suseconds_t microseconds;
C
for mode in -fsigned-char -funsigned-char; do
    "${CC}" -std=c11 -Werror -fsyntax-only "${mode}" -I"${root}/nolibc/include" "${work}/headers.c"
done
for headers in 'sys/types.h' 'sys/time.h time.h sys/types.h' 'time.h sys/time.h' 'unistd.h' 'stdio.h'; do
    : > "${work}/order.c"
    for header in ${headers}; do printf '#include <%s>\n' "${header}" >> "${work}/order.c"; done
    case "${headers}" in
        unistd.h|stdio.h) echo 'int seeks[] = { SEEK_SET, SEEK_CUR, SEEK_END };' >> "${work}/order.c" ;;
        sys/types.h) echo 'time_t s; suseconds_t us;' >> "${work}/order.c" ;;
        *) echo 'struct timespec t; time_t s; suseconds_t us;' >> "${work}/order.c" ;;
    esac
    "${CC}" -std=c11 -Werror -fsyntax-only -I"${root}/nolibc/include" "${work}/order.c"
done
mkdir -p "${work}/nolibc/include/empty" "${work}/openlibm/include" "${work}/openlibm/src"
(cd "${work}" && sh "${root}/gen_dot_install.sh") > "${work}/generated.install"
if grep -F '*' "${work}/generated.install"; then
    echo 'unmatched install glob escaped into manifest' >&2
    exit 1
fi
echo 'header include orders, C11 limits, seek constants, and empty install globs passed'
