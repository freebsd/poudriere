OVERLAYS="omnibus"
. ./common.bulk.sh

LISTPORTS="misc/foo-CIRCULAR@itself"
do_bulk -c -n ${LISTPORTS}
assert 1 $? "Bulk should fail"

EXPECTED_IGNORED=
EXPECTED_TOBUILD=
EXPECTED_QUEUED=
EXPECTED_LISTED="${LISTPORTS}"

assert_bulk_queue_and_stats
assert_bulk_dry_run

LISTPORTS="misc/foo-CIRCULAR@c"
do_bulk -c -n ${LISTPORTS}
assert 0 $? "Bulk should pass"

EXPECTED_TOBUILD="ports-mgmt/pkg misc/foo-CIRCULAR@d ${LISTPORTS} "
EXPECTED_QUEUED="${EXPECTED_TOBUILD}"
EXPECTED_LISTED="${LISTPORTS}"

assert_bulk_queue_and_stats
assert_bulk_dry_run

LISTPORTS="misc/foo-CIRCULAR@d"
do_bulk -c -n ${LISTPORTS}
assert 0 $? "Bulk should pass"

EXPECTED_TOBUILD="ports-mgmt/pkg ${LISTPORTS}"
EXPECTED_QUEUED="${EXPECTED_TOBUILD}"
EXPECTED_LISTED="${LISTPORTS}"

assert_bulk_queue_and_stats
assert_bulk_dry_run
