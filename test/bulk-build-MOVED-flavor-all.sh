FLAVOR_ALL=all
LISTPORTS="misc/freebsd-release-manifests@${FLAVOR_ALL}"
LISTPORTS_MOVED="misc/freebsd-release-manifests-OLD-MOVED@${FLAVOR_ALL}"
OVERLAYS="omnibus"
. common.bulk.sh

do_bulk -t -c ${LISTPORTS_MOVED}
assert 0 $? "Bulk should pass"

EXPECTED_QUEUED="ports-mgmt/pkg misc/foo misc/freebsd-release-manifests@default misc/freebsd-release-manifests@foo misc/freebsd-release-manifests@bar"
EXPECTED_LISTED="${LISTPORTS}"
EXPECTED_TOBUILD="${EXPECTED_QUEUED}"
EXPECTED_BUILT="${EXPECTED_TOBUILD}"

assert_bulk_queue_and_stats
assert_bulk_build_results

do_pkgclean_smoke
