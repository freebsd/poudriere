LISTPORTS="ports-mgmt/poudriere-devel ports-mgmt/poudriere-devel-dep-IGNORED"
# ports-mgmt/poudriere-devel-dep-IGNORED depends on ports-mgmt/poudriere-devel-IGNORED
# which is IGNORED.
# ports-mgmt/poudriere-devel-dep-IGNORED should be skipped.
# ports-mgmt/poudriere-devel-IGNORED depends on misc/foo but it should
# not show up at all.
OVERLAYS="omnibus"
. ./common.bulk.sh

do_bulk -c -n ${LISTPORTS}
assert 0 $? "Bulk should pass"

# This would default to ports-mgmt/poudriere-devel-dep-IGNORED but it is
# expected to be skipped here.
EXPECTED_IGNORED="ports-mgmt/poudriere-devel-IGNORED"
EXPECTED_SKIPPED="ports-mgmt/poudriere-devel-dep-IGNORED"
EXPECTED_TOBUILD="misc/freebsd-release-manifests@default ports-mgmt/pkg ports-mgmt/poudriere-devel"
EXPECTED_QUEUED="${EXPECTED_TOBUILD} ${EXPECTED_IGNORED} ${EXPECTED_SKIPPED}"
EXPECTED_LISTED="ports-mgmt/poudriere-devel ports-mgmt/poudriere-devel-dep-IGNORED"

assert_bulk_queue_and_stats
assert_bulk_dry_run
