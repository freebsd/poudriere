FLAVOR_DEFAULT_ALL=no

LISTPORTS="misc/foo-FLAVORS-unsorted@IGNORED"
OVERLAYS="overlay omnibus"
. common.bulk.sh

do_bulk -n ${LISTPORTS}
assert 0 $? "Bulk should pass"

# Nothing fancy.
EXPECTED_LISTPORTS_IGNORED="misc/foo-FLAVORS-unsorted@IGNORED"
EXPECTED_IGNORED="misc/foo-FLAVORS-unsorted@IGNORED"
EXPECTED_SKIPPED=

assert_bulk_queue_and_stats
