LISTPORTS="ports-mgmt/poudriere-devel ports-mgmt/poudriere-devel-IGNORED misc/foo"
# ports-mgmt/poudriere-devel-dep-IGNORED should be IGNORED.
# misc/foo should show up.
OVERLAYS="omnibus"
. common.bulk.sh

do_bulk -n ${LISTPORTS}
assert 0 $? "Bulk should pass"

EXPECTED_IGNORED="ports-mgmt/poudriere-devel-IGNORED"
EXPECTED_QUEUED="misc/foo misc/freebsd-release-manifests ports-mgmt/pkg ports-mgmt/poudriere-devel"
EXPECTED_LISTED="misc/foo ports-mgmt/poudriere-devel ports-mgmt/poudriere-devel-IGNORED"

assert_bulk_queue_and_stats
