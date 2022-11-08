LISTPORTS="ports-mgmt/poudriere-devel"
OVERLAYS="omnibus"
IMMUTABLE_BASE=nullfs
. common.bulk.sh

do_bulk -c ${LISTPORTS}
assert 0 $? "Bulk should pass"

EXPECTED_QUEUED="ports-mgmt/pkg misc/freebsd-release-manifests ports-mgmt/poudriere-devel"
EXPECTED_LISTED="ports-mgmt/poudriere-devel"

assert_bulk_queue_and_stats
assert_bulk_build_results
