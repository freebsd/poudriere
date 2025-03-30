LISTPORTS="ports-mgmt/poudriere-devel ports-mgmt/poudriere-devel-IGNORED misc/foo"
# Similar to bulk-ignore-one-dep-but-not-other.sh and bulk-ignore-listed.sh
# ports-mgmt/poudriere-devel-dep-IGNORED should be IGNORED.
# misc/foo should show up.
OVERLAYS="omnibus"
. ./common.bulk.sh

do_bulk -c -n ${LISTPORTS}
assert 0 $? "Bulk should pass"

EXPECTED_IGNORED="ports-mgmt/poudriere-devel-IGNORED"
EXPECTED_TOBUILD="misc/foo@default:listed misc/freebsd-release-manifests@default ports-mgmt/pkg ports-mgmt/poudriere-devel"
EXPECTED_QUEUED="${EXPECTED_TOBUILD} ${EXPECTED_IGNORED} ${EXPECTED_SKIPPED}"
EXPECTED_LISTED="misc/foo@default ports-mgmt/poudriere-devel ports-mgmt/poudriere-devel-IGNORED"

assert_bulk_queue_and_stats
assert_bulk_dry_run
