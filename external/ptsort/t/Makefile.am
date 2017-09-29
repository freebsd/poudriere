AM_CPPFLAGS = -I$(top_srcdir)/lib
LIBPSORT = $(top_builddir)/lib/libptsort.a

if WITH_TESTS

check_PROGRAMS = t_aa
t_aa_LDADD = $(LIBPSORT) $(LIBCRYB_TEST)

dist_check_SCRIPTS = t_dp_red.sh

${dist_check_SCRIPTS}: t_subr.sh

EXTRA_DIST = t_dp_red.ti t_dp_red.to

TESTS = $(check_PROGRAMS) $(dist_check_SCRIPTS)

CLEANFILES = t_subr.sh

endif
