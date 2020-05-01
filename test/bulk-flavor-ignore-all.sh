ALL=1
OVERLAYS="omnibus"
. common.bulk.sh

do_bulk -n -a
assert 0 $? "Bulk should pass"

EXPECTED_IGNORED="misc/foo@IGNORED ports-mgmt/poudriere-devel-IGNORED ports-mgmt/poudriere-devel-IGNORED-and-skipped"
EXPECTED_SKIPPED="ports-mgmt/poudriere-devel-dep-IGNORED ports-mgmt/poudriere-devel-dep2-IGNORED"

assert_bulk_queue_and_stats
