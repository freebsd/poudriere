LISTPORTS="misc/foo-FLAVORS-unsorted@default misc/foo-dep-FLAVORS-unsorted@default"
# misc/foo-FLAVORS-unsorted@default build depends on misc/foo-dep-FLAVORS-unsorted@default
OVERLAYS="omnibus"
. ./common.bulk.sh

set_test_contexts - '' '' <<-EOF
TRIM_ORPHANED_BUILD_DEPS no yes
EOF

while get_test_context; do
	set_poudriere_conf <<-EOF
	TRIM_ORPHANED_BUILD_DEPS=${TRIM_ORPHANED_BUILD_DEPS}
	EOF

	do_pkgclean -y ports-mgmt/pkg
	assert 0 "$?" "Pkgclean should pass"

	# Build pkg only once as this is a long test otherwise.
	do_bulk ports-mgmt/pkg
	assert 0 "$?" "bulk for pkg should pass"

	EXPECTED_IGNORED=
	EXPECTED_SKIPPED=
	EXPECTED_TOBUILD="misc/foo-FLAVORS-unsorted@default misc/foo-dep-FLAVORS-unsorted@default"
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

	# Now delete the *build* depend.
	do_pkgclean -y -C misc/foo-dep-FLAVORS-unsorted@default
	assert 0 "$?" "Pkgclean should pass"

	# Because misc/foo-dep-FLAVORS-unsorted@default is *listed* it will
	# still be built regardless of TRIM_ORPHANED_BUILD_DEPS.
	EXPECTED_TOBUILD="misc/foo-dep-FLAVORS-unsorted@default"

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
