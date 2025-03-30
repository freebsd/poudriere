LISTPORTS="misc/foo-flavor-double-DEPIGNORED@depignored"
OVERLAYS="omnibus"
. ./common.bulk.sh

: ${ASSERT_CONTINUE:=0}
set_test_contexts - '' '' <<-EOF
JFLAG 1:1 4:4
EOF
while get_test_context; do
	do_bulk -c -n ${LISTPORTS}
	assert 0 $? "Bulk should pass"

	EXPECTED_IGNORED="misc/foo-dep-FLAVORS-unsorted@depignored misc/foo-all-IGNORED"
	EXPECTED_SKIPPED="misc/foo-flavor-double-DEPIGNORED@depignored"
	EXPECTED_TOBUILD="ports-mgmt/pkg"
	EXPECTED_QUEUED="${EXPECTED_TOBUILD} ${EXPECTED_IGNORED} ${EXPECTED_SKIPPED}"
	EXPECTED_LISTED="${LISTPORTS}"

	assert_bulk_queue_and_stats
	assert_bulk_dry_run
done
