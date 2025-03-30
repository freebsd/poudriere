FLAVOR_ALL=all
LISTPORTS="misc/foo-flavor-double-DEPIGNORED@${FLAVOR_ALL}"
# This is testing that non-default FLAVOR will be considered IGNORE rather
# than SKIPPED for a listed port@all. See e158cb8814fa6a24e9c4c5344a67d67d9d5a418e.
# Additionally this test, vs the ones in that commit, will have a FLAVOR that
# is *double* skipped. I.e., it has 2 dependencies which are IGNORED.
# Test that this port does not get double IGNORED
OVERLAYS="omnibus"
. ./common.bulk.sh

: ${ASSERT_CONTINUE:=0}
set_test_contexts - '' '' <<-EOF
JFLAG 1:1 4:4
EOF
while get_test_context; do
	do_bulk -c -n ${LISTPORTS}
	assert 0 $? "Bulk should pass"

	EXPECTED_IGNORED="misc/foo-flavor-double-DEPIGNORED@depignored misc/foo-dep-FLAVORS-unsorted@depignored misc/foo-all-IGNORED"
	EXPECTED_SKIPPED=
	EXPECTED_TOBUILD="misc/foo-flavor-double-DEPIGNORED@default ports-mgmt/pkg"
	EXPECTED_QUEUED="${EXPECTED_TOBUILD} ${EXPECTED_IGNORED} ${EXPECTED_SKIPPED}"
	EXPECTED_LISTED="${LISTPORTS}"

	assert_bulk_queue_and_stats
	assert_bulk_dry_run
done
