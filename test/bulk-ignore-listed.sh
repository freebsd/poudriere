LISTPORTS="ports-mgmt/poudriere-devel ports-mgmt/poudriere-devel-IGNORED"
# ports-mgmt/poudriere-devel-IGNORED depends on misc/foo but it should
# not show up at all.
OVERLAYS="omnibus"
. common.bulk.sh

do_bulk -n ${LISTPORTS}
assert 0 $? "Bulk should pass"

EXPECTED_IGNORED="ports-mgmt/poudriere-devel-IGNORED"
EXPECTED_SKIPPED=
EXPECTED_QUEUED="misc/freebsd-release-manifests@default ports-mgmt/pkg ports-mgmt/poudriere-devel"
EXPECTED_LISTED="ports-mgmt/poudriere-devel ports-mgmt/poudriere-devel-IGNORED"

assert_bulk_queue_and_stats
