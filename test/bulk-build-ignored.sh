OVERLAYS="omnibus"
LISTPORTS="misc/foo@ignored"
. ./common.bulk.sh

EXPECTED_QUEUED="${LISTPORTS}"
EXPECTED_LISTED="${LISTPORTS}"
EXPECTED_TOBUILD=
EXPECTED_IGNORED="${LISTPORTS}"
EXPECTED_BUILT=
do_bulk -T -c -n ${LISTPORTS}
assert 0 "$?" "bulk dry-run should pass"
assert_bulk_queue_and_stats
assert_bulk_build_results
echo "-----" | tee /dev/stderr

EXPECTED_IGNORED="${LISTPORTS}"
do_bulk -T -c ${LISTPORTS}
assert 0 "$?" "bulk should pass"
assert_bulk_queue_and_stats
assert_bulk_build_results
echo "-----" | tee /dev/stderr
