LISTPORTS="misc/freebsd-release-manifests@DEFAULT ports-mgmt/poudriere-devel"
OVERLAYS="omnibus"
. common.bulk.sh

do_bulk -n ${LISTPORTS}
assert 0 $? "Bulk should pass"

EXPECTED_QUEUED="misc/freebsd-release-manifests ports-mgmt/pkg ports-mgmt/poudriere-devel"
EXPECTED_LISTED="misc/freebsd-release-manifests ports-mgmt/poudriere-devel"

assert_bulk_queue_and_stats
