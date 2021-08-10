LISTPORTS="ports-mgmt/poudriere-devel ports-mgmt/poudriere-devel-IGNORED-and-skipped"
# IGNORE should take precedence over skipped.
OVERLAYS="omnibus"
. common.bulk.sh

do_bulk -n ${LISTPORTS}
assert 0 $? "Bulk should pass"

EXPECTED_LISTPORTS_IGNORED="ports-mgmt/poudriere-devel-IGNORED-and-skipped"
# ports-mgmt/poudriere-devel-IGNORED is a dependency which is also ignored but
# because we are ignoring ports-mgmt/poudriere-devel-IGNORED-and-skipped we
# should not bother processing ports-mgmt/poudriere-devel-IGNORED at all.
EXPECTED_IGNORED="ports-mgmt/poudriere-devel-IGNORED-and-skipped"
EXPECTED_SKIPPED=
assert_bulk_queue_and_stats
