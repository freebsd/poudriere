LISTPORTS="ports-mgmt/poudriere-devel"
OVERLAYS="omnibus"
IMMUTABLE_BASE=schg
. ./common.bulk.sh

do_bulk -t -c ${LISTPORTS}
assert 0 $? "Bulk should pass"

EXPECTED_QUEUED="ports-mgmt/pkg misc/freebsd-release-manifests@default ports-mgmt/poudriere-devel"
EXPECTED_LISTED="ports-mgmt/poudriere-devel"
EXPECTED_TOBUILD="${EXPECTED_QUEUED}"
EXPECTED_BUILT="${EXPECTED_TOBUILD}"

assert_bulk_queue_and_stats
assert_bulk_build_results

do_pkgclean_smoke
