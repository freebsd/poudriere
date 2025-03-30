# This test covers basic MOVED *and* bringing along the requested FLAVOR.
LISTPORTS="misc/freebsd-release-manifests@default"
LISTPORTS_MOVED="misc/freebsd-release-manifests-OLD-MOVED@optional"
OVERLAYS="omnibus"
. ./common.bulk.sh

do_bulk -c -n ${LISTPORTS_MOVED}
assert 0 $? "Bulk should pass"

EXPECTED_QUEUED="${LISTPORTS}:listed ports-mgmt/pkg"
EXPECTED_LISTED="${LISTPORTS}"
EXPECTED_TOBUILD="${EXPECTED_QUEUED}"

assert_bulk_queue_and_stats
assert_bulk_dry_run
