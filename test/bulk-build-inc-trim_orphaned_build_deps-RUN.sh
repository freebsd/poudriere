LISTPORTS="misc/foo-RUNDEP-misc-foo"
# Similar to bulk-build-inc-trim_orphaned_build_deps.sh but uses RUN_DEPENDS.
# misc/foo-RUNDEP-misc-foo RUN depends on misc/foo@default
OVERLAYS="omnibus misc"
. ./common.bulk.sh

set_test_contexts - '' '' <<-EOF
TRIM_ORPHANED_BUILD_DEPS no yes
SKIP_RECURSIVE_REBUILD 0 1
EOF

while get_test_context; do
	set_poudriere_conf <<-EOF
	TRIM_ORPHANED_BUILD_DEPS=${TRIM_ORPHANED_BUILD_DEPS}
	SKIP_RECURSIVE_REBUILD=${SKIP_RECURSIVE_REBUILD}
	EOF

	do_pkgclean -y ports-mgmt/pkg
	assert 0 "$?" "Pkgclean should pass"

	# Build pkg only once as this is a long test otherwise.
	do_bulk ports-mgmt/pkg
	assert 0 "$?" "bulk for pkg should pass"

	EXPECTED_IGNORED=
	EXPECTED_SKIPPED=
	EXPECTED_TOBUILD="misc/foo-RUNDEP-misc-foo misc/foo@default"
	EXPECTED_QUEUED="${EXPECTED_TOBUILD}"
	EXPECTED_LISTED="${LISTPORTS}"
	EXPECTED_BUILT=
	do_bulk -n ${LISTPORTS}
	assert 0 $? "Bulk should pass"
	assert_bulk_queue_and_stats
	assert_bulk_dry_run
	echo "------" | tee /dev/stderr

	EXPECTED_BUILT="${EXPECTED_TOBUILD}"
	do_bulk ${LISTPORTS}
	assert 0 $? "Bulk should pass"
	assert_bulk_queue_and_stats
	assert_bulk_build_results
	echo "------" | tee /dev/stderr

	# Now delete the *run* depend.
	do_pkgclean -y -C misc/foo@default
	assert 0 "$?" "Pkgclean should pass"

	# Regardless of TRIM_ORPHANED_BUILD_DEPS we must always have our
	# RUN_DEPENDS available. misc/foo@default should build for
	# misc/foo-RUNDEP-misc-foo.
	EXPECTED_TOBUILD="misc/foo@default"
	# Recursive rebuild does sneak into here to fix potential problems.
	# So it is tested OFF as well.
	case "${PKG_NO_VERSION_FOR_DEPS-}.${SKIP_RECURSIVE_REBUILD}" in
	yes.*) ;;
	*.0)
		EXPECTED_TOBUILD="${EXPECTED_TOBUILD} misc/foo-RUNDEP-misc-foo"
		;;
	esac
	EXPECTED_QUEUED="${EXPECTED_TOBUILD}"
	EXPECTED_BUILT=
	do_bulk -n ${LISTPORTS}
	assert 0 $? "Bulk should pass"
	assert_bulk_queue_and_stats
	assert_bulk_dry_run
	echo "------" | tee /dev/stderr

	EXPECTED_BUILT="${EXPECTED_TOBUILD}"
	do_bulk ${LISTPORTS}
	assert 0 $? "Bulk should pass"
	assert_bulk_queue_and_stats
	assert_bulk_build_results
	echo "------" | tee /dev/stderr
done
