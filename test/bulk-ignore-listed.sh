LISTPORTS="ports-mgmt/poudriere-devel ports-mgmt/poudriere-devel-IGNORED"
# ports-mgmt/poudriere-devel-IGNORED depends on misc/foo but it should
# not show up at all.
OVERLAYS="omnibus"
. common.bulk.sh

do_bulk -n ${LISTPORTS}
assert 0 $? "Bulk should pass"

EXPECTED_LISTPORTS_IGNORED="ports-mgmt/poudriere-devel-IGNORED"
EXPECTED_IGNORED="ports-mgmt/poudriere-devel-IGNORED"
EXPECTED_SKIPPED=
assert_bulk_queue_and_stats
