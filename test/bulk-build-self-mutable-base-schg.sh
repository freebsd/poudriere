LISTPORTS="ports-mgmt/poudriere-devel"
OVERLAYS="omnibus"
MUTABLE_BASE=schg
. common.bulk.sh

do_bulk -c ${LISTPORTS}
assert 0 $? "Bulk should pass"

assert_bulk_queue_and_stats
