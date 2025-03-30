LISTPORTS="misc/freebsd-release-manifests@all misc/freebsd-release-manifests@foo"
OVERLAYS="omnibus"
. ./common.bulk.sh

do_bulk -c -n ${LISTPORTS}
assert 0 $? "Bulk should pass"

EXPECTED_QUEUED="misc/foo misc/freebsd-release-manifests misc/freebsd-release-manifests@bar misc/freebsd-release-manifests@foo ports-mgmt/pkg"
EXPECTED_LISTED="misc/freebsd-release-manifests misc/freebsd-release-manifests@bar misc/freebsd-release-manifests@foo"

assert_bulk_queue_and_stats
assert_bulk_dry_run
