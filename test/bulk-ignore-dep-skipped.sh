LISTPORTS="ports-mgmt/poudriere-devel ports-mgmt/poudriere-devel-dep-IGNORED"
# ports-mgmt/poudriere-devel-dep-IGNORED depends on ports-mgmt/poudriere-devel-IGNORED
# which is IGNORED.
# ports-mgmt/poudriere-devel-dep-IGNORED should be skipped.
# ports-mgmt/poudriere-devel-IGNORED depends on misc/foo but it should
# not show up at all.
OVERLAYS="omnibus"
. common.bulk.sh

do_bulk -n ${LISTPORTS}
assert 0 $? "Bulk should pass"

EXPECTED_LISTPORTS_NOIGNORED="ports-mgmt/poudriere-devel"
# This would default to ports-mgmt/poudriere-devel-dep-IGNORED but it is
# expected to be skipped here.
EXPECTED_LISTPORTS_IGNORED=
EXPECTED_IGNORED="ports-mgmt/poudriere-devel-IGNORED"
EXPECTED_SKIPPED="ports-mgmt/poudriere-devel-dep-IGNORED"

assert_bulk_queue_and_stats
