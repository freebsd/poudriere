OVERLAYS="omnibus"
LISTPORTS="misc/foo@broken"
. ./common.bulk.sh

EXPECTED_QUEUED="${LISTPORTS}"
EXPECTED_LISTED="${LISTPORTS}"
EXPECTED_TOBUILD=
EXPECTED_IGNORED="${LISTPORTS}"
EXPECTED_BUILT=
do_bulk -c -n ${LISTPORTS}
assert 0 "$?" "bulk dry-run should pass"
assert_bulk_queue_and_stats
assert_bulk_build_results
echo "-----" | tee /dev/stderr

# Try again with -T

EXPECTED_QUEUED="ports-mgmt/pkg ${LISTPORTS}"
EXPECTED_LISTED="${LISTPORTS}"
EXPECTED_TOBUILD="${EXPECTED_QUEUED}"
EXPECTED_IGNORED=
EXPECTED_BUILT=
do_bulk -T -c -n ${LISTPORTS}
assert 0 "$?" "bulk dry-run should pass"
assert_bulk_queue_and_stats
assert_bulk_build_results
echo "-----" | tee /dev/stderr

EXPECTED_BUILT="${EXPECTED_TOBUILD}"
do_bulk -T -c ${LISTPORTS}
assert 0 "$?" "bulk should pass"
assert_bulk_queue_and_stats
assert_bulk_build_results
echo "-----" | tee /dev/stderr
