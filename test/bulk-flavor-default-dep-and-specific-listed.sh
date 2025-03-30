LISTPORTS="misc/freebsd-release-manifests@foo ports-mgmt/poudriere-devel"
OVERLAYS="omnibus"
. ./common.bulk.sh

do_bulk -c -n ${LISTPORTS}
assert 0 $? "Bulk should pass"

EXPECTED_QUEUED="misc/foo@default misc/freebsd-release-manifests@default misc/freebsd-release-manifests@foo ports-mgmt/pkg ports-mgmt/poudriere-devel"
EXPECTED_LISTED="misc/freebsd-release-manifests@foo ports-mgmt/poudriere-devel"

assert_bulk_queue_and_stats
assert_bulk_dry_run
