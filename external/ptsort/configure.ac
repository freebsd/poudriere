AC_PREREQ([2.63])
AC_INIT([ptsort], [1.20170904], [des@des.no],
    [ptsort], [https://www.github.com/dag-erling/ptsort])
AC_CONFIG_SRCDIR([bin/ptsort.c])
AC_CONFIG_MACRO_DIR([m4])
AM_INIT_AUTOMAKE([foreign subdir-objects])
AM_CONFIG_HEADER(lib/config.h)

# C compiler and features
AC_LANG(C)
AC_PROG_CC
AC_PROG_CC_STDC
AC_PROG_CPP
AC_GNU_SOURCE
AC_C_CONST
AC_C_VOLATILE

# other programs
AC_PROG_INSTALL
AC_PROG_RANLIB

# libraries
save_LIBS="${LIBS}"
LIBS=""
AC_CHECK_LIB([cryb-test], [t_add_tests])
LIBCRYB_TEST="${LIBS}"
LIBS="${save_LIBS}"
AC_SUBST(LIBCRYB_TEST)
AM_CONDITIONAL([WITH_TESTS], [test x"${LIBCRYB_TEST}" != x""])

# options
AC_ARG_ENABLE([developer-warnings],
    AS_HELP_STRING([--enable-developer-warnings], [enable strict warnings (default is NO)]),
    [CFLAGS="${CFLAGS} -Wall -Wextra -Wcast-qual -Wshadow"])
AC_ARG_ENABLE([debugging-symbols],
    AS_HELP_STRING([--enable-debugging-symbols], [enable debugging symbols (default is NO)]),
    [CFLAGS="${CFLAGS} -O0 -g -fno-inline"])
AC_ARG_ENABLE([werror],
    AS_HELP_STRING([--enable-werror], [use -Werror (default is NO)]),
    [CFLAGS="${CFLAGS} -Werror"])

# output
AC_CONFIG_FILES([
    Makefile
    bin/Makefile
    lib/Makefile
    t/Makefile
    t/t_subr.sh
])
AC_OUTPUT
