LISTPORTS="ports-mgmt/poudriere-devel-dep-IGNORED misc/freebsd-release-manifests"
# porta -> portb -> portc
# list -> ignore -> skip(and listed)
# ports-mgmt/poudriere-devel-dep-IGNORED -> ports-mgmt/poudriere-devel-IGNORED -> misc/freebsd-release-manifests
# list also portc

# ports-mgmt/poudriere-devel-dep-IGNORED depends on ports-mgmt/poudriere-devel-IGNORED
# which is IGNORED.
# ports-mgmt/poudriere-devel-dep-IGNORED should be skipped.
# ports-mgmt/poudriere-devel-IGNORED depends on misc/freebsd-release-manifests which is skipped
# but misc/freebsd-release-manifests is listed so should be queued.
OVERLAYS="omnibus"
. ./common.bulk.sh

do_bulk -c -n ${LISTPORTS}
assert 0 $? "Bulk should pass"

EXPECTED_IGNORED="ports-mgmt/poudriere-devel-IGNORED"
EXPECTED_SKIPPED="ports-mgmt/poudriere-devel-dep-IGNORED"
EXPECTED_QUEUED="misc/freebsd-release-manifests@default ports-mgmt/pkg ports-mgmt/poudriere-devel-IGNORED ports-mgmt/poudriere-devel-dep-IGNORED"
EXPECTED_TOBUILD="misc/freebsd-release-manifests@default ports-mgmt/pkg"
EXPECTED_LISTED="misc/freebsd-release-manifests@default ports-mgmt/poudriere-devel-dep-IGNORED"

assert_bulk_queue_and_stats
assert_bulk_dry_run
