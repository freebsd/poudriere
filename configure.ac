AC_INIT([poudriere],[3.0.99],[https://fossil.etoilebsd.net/poudriere],[poudriere])
AC_CONFIG_SRCDIR([configure.ac])
AM_INIT_AUTOMAKE([1.11 foreign -Wall -Wno-portability no-dist-gzip dist-xz])
AM_SILENT_RULES([yes])
AC_CONFIG_HEADER(src/config.h)

AC_PROG_CC
AC_PROG_RANLIB

AC_CHECK_FUNCS([strftime_l])

AC_CONFIG_FILES(Makefile)

AC_OUTPUT([src/etc/rc.d/poudriered])
