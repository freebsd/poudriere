FLAVOR_DEFAULT_ALL=no
FLAVOR_ALL=all
LISTPORTS="misc/foo-FLAVORS-unsorted@${FLAVOR_ALL}"
OVERLAYS="omnibus"
. common.bulk.sh

do_bulk -n ${LISTPORTS}
assert 0 $? "Bulk should pass"

EXPECTED_IGNORED="misc/foo-FLAVORS-unsorted@IGNORED"

assert_bulk_queue_and_stats
