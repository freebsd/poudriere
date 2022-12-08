MOSTLYCLEANFILES=
MOSTLYCLEANFILES+=	$(TEST_LOGS:.log=.log.truss)
MOSTLYCLEANFILES+=	$(TEST_LOGS:.log=*.log)

EXTRA_DIST= $(TESTS) \
	    $(JAIL_TESTS) \
	    common.bulk.sh \
	    common.locked_mkdir.sh \
	    common.sh \
	    prep.sh \
	    runtest.sh

XFAIL_TESTS= \
	distclean-overlays.sh

TESTS=\
	builtins.sh \
	cache.sh \
	cache_pipe.sh \
	calculate_duration.sh \
	count_lines.sh \
	display.sh \
	distclean-badorigin.sh \
	distclean-overlays.sh \
	distclean-smoke.sh \
	do_clone.sh \
	encode_args.sh \
	getpid.sh \
	getvar.sh \
	gsub.sh \
	globmatch.sh \
	hash_basic.sh \
	hash_stack.sh \
	list.sh \
	locks.sh \
	locks_critical_section.sh \
	locks_critical_section_nested.sh \
	locked_mkdir.sh \
	locked_mkdir_waiters.sh \
	locked_mkdir_waiters_kill.sh \
	locked_mkdir_waiters_all_lose.sh \
	logging.sh \
	mapfile.sh \
	mktemp.sh \
	originspec.sh \
	pkg_version.sh \
	pipe_func.sh \
	pipe_hold.sh \
	port_var_fetch.sh \
	prefix_output.sh \
	read_blocking.sh \
	read_file.sh \
	relpath.sh \
	relpath_common.sh \
	required_env.sh \
	shash_basic.sh \
	stack.sh \
	stripansi.sh \
	test_contexts.sh \
	test_contexts_expand.sh \
	timespec.sh \
	timestamp.sh \
	trap_ignore_block.sh \
	trap_save_block.sh \
	trap_save.sh \
	$(JAIL_TESTS)

JAIL_TESTS= \
	bulk-build-inc-pkgclean-flavor-default.sh \
	bulk-build-inc-pkgclean-flavor.sh \
	bulk-build-inc-pkgclean-origin.sh \
	bulk-build-multiple-eligible-in-queue.sh \
	bulk-build-self-immutable-base-nullfs.sh \
	bulk-build-self-immutable-base-schg.sh \
	bulk-build-self-immutable-base-yes.sh \
	bulk-flavor-FLAVORS-misordered.sh \
	bulk-flavor-all-and-specific.sh \
	bulk-flavor-default-dep-and-specific-listed.sh \
	bulk-flavor-default-dep.sh \
	bulk-flavor-ignore-all.sh \
	bulk-flavor-ignore-vs-skip-listed-all-depignored-other.sh \
	bulk-flavor-ignore-vs-skip-listed-all-depignored.sh \
	bulk-flavor-ignore-vs-skip-listed-all.sh \
	bulk-flavor-ignore-vs-skip-listed-default-all.sh \
	bulk-flavor-ignore-vs-skip-listed-default-depignored-other.sh \
	bulk-flavor-ignore-vs-skip-listed-default-depignored.sh \
	bulk-flavor-ignore-vs-skip-listed-default-ignored-other.sh \
	bulk-flavor-ignore-vs-skip-listed-default-ignored.sh \
	bulk-flavor-ignore-vs-skip-listed-default.sh \
	bulk-flavor-ignore-vs-skip-listed-flavor-ignored.sh \
	bulk-flavor-ignore-vs-skip-listed-flavor.sh \
	bulk-flavor-main-dep-and-default-listed.sh \
	bulk-flavor-main-dep-and-specific-listed.sh \
	bulk-flavor-main-dep.sh \
	bulk-flavor-metadata-queue-ordering-multi-pass.sh \
	bulk-flavor-metadata-queue-ordering.sh \
	bulk-flavor-nonexistent.sh \
	bulk-flavor-specific-dep-and-default-listed.sh \
	bulk-flavor-specific-dep-and-default-shorthand-listed.sh \
	bulk-flavor-specific-dep-and-main-listed_default_all_off.sh \
	bulk-flavor-specific-dep-and-main-listed_default_all_off_w_@all.sh \
	bulk-flavor-specific-dep-and-main-listed_default_all_on.sh \
	bulk-flavor-specific-dep-and-multi-listed.sh \
	bulk-flavor-specific-dep-and-multi-no-main-listed.sh \
	bulk-flavor-specific-dep-and-specific-listed-nonexistent.sh \
	bulk-flavor-specific-dep-and-specific-listed.sh \
	bulk-flavor-specific-dep-nonexistent.sh \
	bulk-flavor-specific-dep.sh \
	bulk-ignore-and-skipped.sh \
	bulk-ignore-dep-skipped.sh \
	bulk-ignore-listed-dep.sh \
	bulk-ignore-listed-skipped-dep.sh \
	bulk-ignore-listed.sh \
	bulk-no-overlay-specific.sh \
	bulk-overlay-all.sh \
	bulk-overlay-specific.sh \
	bulk-skipped-and-needed-dep.sh \
	testport-all-flavors-failure.sh \
	testport-build-default-flavor.sh \
	testport-build-no-deps.sh \
	testport-build-specific-flavor.sh \
	testport-build-specific-port.sh \
	testport-default-all-flavors-failure.sh \
	testport-specific-bad-flavor-failure.sh

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
