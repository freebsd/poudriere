FLAVOR_ALL=all
LISTPORTS="misc/freebsd-release-manifests@${FLAVOR_ALL}"
LISTPORTS_MOVED="misc/freebsd-release-manifests-OLD-MOVED@${FLAVOR_ALL}"
OVERLAYS="omnibus"
. ./common.bulk.sh

do_bulk -c -n ${LISTPORTS_MOVED}
assert 0 $? "Bulk should pass"

EXPECTED_QUEUED="ports-mgmt/pkg misc/foo misc/freebsd-release-manifests@default:listed misc/freebsd-release-manifests@foo:listed misc/freebsd-release-manifests@bar:listed"
EXPECTED_LISTED="${LISTPORTS}"
EXPECTED_TOBUILD="${EXPECTED_QUEUED}"

assert_bulk_queue_and_stats
assert_bulk_dry_run
