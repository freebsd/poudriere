LISTPORTS="ports-mgmt/pkg"
. ./common.bulk.sh

EXPECTED_IGNORED=
EXPECTED_INSPECTED=
EXPECTED_SKIPPED=
EXPECTED_TOBUILD="${LISTPORTS}"
EXPECTED_QUEUED="${EXPECTED_TOBUILD}"
EXPECTED_LISTED="${LISTPORTS}"
EXPECTED_BUILT=
do_bulk -c -n ${LISTPORTS}
assert 0 $? "Bulk should pass"
assert_bulk_queue_and_stats
assert_bulk_dry_run
echo "------" | tee /dev/stderr

EXPECTED_BUILT="${EXPECTED_TOBUILD}"
do_bulk -c ${LISTPORTS}
assert 0 $? "Bulk should pass"
assert_bulk_queue_and_stats
assert_bulk_build_results
echo "------" | tee /dev/stderr
