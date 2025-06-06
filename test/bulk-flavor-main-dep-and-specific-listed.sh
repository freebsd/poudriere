LISTPORTS="misc/freebsd-release-manifests@foo ports-mgmt/poudriere-devel-dep-DEFAULT"
OVERLAYS="omnibus"
. ./common.bulk.sh

do_bulk -c -n ${LISTPORTS}
assert 0 $? "Bulk should pass"

EXPECTED_QUEUED="misc/foo@default misc/freebsd-release-manifests@default misc/freebsd-release-manifests@foo ports-mgmt/pkg ports-mgmt/poudriere-devel-dep-DEFAULT"
EXPECTED_LISTED="misc/freebsd-release-manifests@foo ports-mgmt/poudriere-devel-dep-DEFAULT"

assert_bulk_queue_and_stats
assert_bulk_dry_run
