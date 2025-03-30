LISTPORTS="ports-mgmt/poudriere-devel ports-mgmt/poudriere-devel-IGNORED misc/freebsd-release-manifests@foo"
# Similar to bulk-ignore-listed-dep.sh and bulk-ignore-listed.sh
# ports-mgmt/poudriere-devel-IGNORED depends on misc/foo which won't add
# to the queue, but misc/freebsd-release-manifests@foo does depend on it
# so it will add it to the queue.
OVERLAYS="omnibus"
. ./common.bulk.sh

do_bulk -c -n ${LISTPORTS}
assert 0 $? "Bulk should pass"

EXPECTED_IGNORED="ports-mgmt/poudriere-devel-IGNORED"
EXPECTED_SKIPPED=
EXPECTED_TOBUILD="misc/freebsd-release-manifests@default ports-mgmt/pkg ports-mgmt/poudriere-devel misc/freebsd-release-manifests@foo misc/foo@default:misc/freebsd-release-manifests@foo"
EXPECTED_QUEUED="${EXPECTED_TOBUILD} ${EXPECTED_IGNORED} ${EXPECTED_SKIPPED}"
EXPECTED_LISTED="ports-mgmt/poudriere-devel ports-mgmt/poudriere-devel-IGNORED misc/freebsd-release-manifests@foo"

assert_bulk_queue_and_stats
assert_bulk_dry_run
