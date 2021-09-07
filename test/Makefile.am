EXTRA_DIST= $(TESTS) \
	    $(JAIL_TESTS) \
	    common.bulk.sh \
	    common.locked_mkdir.sh \
	    common.sh \
	    prep.sh \
	    runtest.sh
TESTS=\
	builtins.sh \
	cache.sh \
	do_clone.sh \
	encode_args.sh \
	getpid.sh \
	getvar.sh \
	gsub.sh \
	hash_basic.sh \
	list.sh \
	locks.sh \
	locks_critical_section.sh \
	locks_critical_section_nested.sh \
	locked_mkdir.sh \
	locked_mkdir_waiters.sh \
	locked_mkdir_waiters_kill.sh \
	locked_mkdir_waiters_all_lose.sh \
	mapfile.sh \
	port_var_fetch.sh \
	prefix_output.sh \
	read_blocking.sh \
	read_file.sh \
	relpath.sh \
	relpath_common.sh \
	shash_basic.sh \
	timespec.sh \
	timestamp.sh \
	trap_save.sh \
	$(JAIL_TESTS)

JAIL_TESTS= \
	bulk-bad-DEPENDS_ARGS.sh \
	bulk-ignore-listed.sh \
	bulk-ignore-dep-skipped.sh \
	bulk-ignore-listed-skipped-dep.sh \
	bulk-ignore-listed-dep.sh \
	bulk-ignore-and-skipped.sh \
	bulk-flavor-default-dep-and-specific-listed.sh \
	bulk-flavor-default-dep.sh \
	bulk-flavor-main-dep-and-default-listed.sh \
	bulk-flavor-main-dep-and-specific-listed.sh \
	bulk-flavor-main-dep.sh \
	bulk-flavor-nonexistent.sh \
	bulk-flavor-specific-dep-and-default-listed.sh \
	bulk-flavor-specific-dep-and-default-shorthand-listed.sh \
	bulk-flavor-specific-dep-and-main-listed_default_all_off.sh \
	bulk-flavor-specific-dep-and-main-listed_default_all_off_w_@all.sh \
	bulk-flavor-specific-dep-and-main-listed_default_all_on.sh \
	bulk-flavor-specific-dep-and-multi-listed.sh \
	bulk-flavor-specific-dep-and-multi-no-main-listed.sh \
	bulk-flavor-specific-dep-and-specific-listed.sh \
	bulk-flavor-specific-dep-and-specific-listed-nonexistent.sh \
	bulk-flavor-specific-dep-nonexistent.sh \
	bulk-flavor-specific-dep.sh \
	bulk-flavor-metadata-queue-ordering.sh \
	bulk-flavor-metadata-queue-ordering-multi-pass.sh \
	bulk-flavor-ignore-all.sh \
	bulk-overlay-all.sh \
	bulk-no-overlay-specific.sh \
	bulk-overlay-specific.sh \
	bulk-build-self-immutable-base-yes.sh \
	bulk-build-self-immutable-base-schg.sh \
	bulk-build-self-immutable-base-nullfs.sh

# Depend bulk tests on jail setup
TESTS+=	prep.sh
$(JAIL_TESTS:.sh=.sh.log): prep.sh.log

run_env= env \
	 abs_top_builddir="$(abs_top_builddir)" \
	 abs_top_srcdir="$(abs_top_srcdir)" \
	 bindir="$(bindir)" \
	 pkglibexecdir="$(pkglibexecdir)" \
	 pkgdatadir="$(pkgdatadir)" \
	 VPATH="$(VPATH)" \
	 am_check=1
LOG_COMPILER=	$(run_env) $(SHELL) $(srcdir)/runtest.sh

.PHONY: prep
prep:
	@echo "Prepping test jail"
	@$(LOG_COMPILER) $(srcdir)/prep.sh
#TEST_EXTENSIONS=.sh
#SH_LOG_COMPILER=$(run_env) $(SHELL) runtest.sh
