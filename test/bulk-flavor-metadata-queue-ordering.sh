# first depends on a specific flavor
# second depends on the default flavor
# The order matters here since listed_ports does a sort -u. The specific
# FLAVOR dependency MUST come first to hit the bug.
LISTPORTS="ports-mgmt/poudriere-devel-dep-FOO ports-mgmt/zzzz"
OVERLAYS="omnibus"
. common.bulk.sh

do_bulk -n ${LISTPORTS}
assert 0 $? "Bulk should pass"

assert_bulk_queue_and_stats
