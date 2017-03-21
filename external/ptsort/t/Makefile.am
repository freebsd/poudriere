AM_CPPFLAGS = -I$(top_srcdir)/lib
LIBPSORT = $(top_builddir)/lib/libptsort.a

if WITH_TESTS

check_PROGRAMS = t_aa
t_aa_LDADD = $(LIBPSORT) $(LIBCRYB_TEST)

TESTS = $(check_PROGRAMS)

endif
