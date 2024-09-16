AM_CPPFLAGS = -I$(top_srcdir)/lib
LIBPSORT = $(top_builddir)/lib/libptsort.a

check_PROGRAMS=
dist_check_SCRIPTS =
EXTRA_DIST =

if WITH_CRYB_TEST
check_PROGRAMS += t_aa
t_aa_LDADD = $(LIBPSORT) $(LIBCRYB_TEST)
endif

dist_check_SCRIPTS += t_dp_red.sh
EXTRA_DIST += t_dp_red.ti
EXTRA_DIST += t_dp_red.to

dist_check_SCRIPTS += t_parallel.sh
EXTRA_DIST += t_parallel.ti
EXTRA_DIST += t_parallel-dp.to
EXTRA_DIST += t_parallel-PDd.to
EXTRA_DIST += t_parallel-Pp.to
EXTRA_DIST += t_parallel-P.to

${dist_check_SCRIPTS}: t_subr.sh

TESTS = $(check_PROGRAMS) $(dist_check_SCRIPTS)

CLEANFILES = t_subr.sh
