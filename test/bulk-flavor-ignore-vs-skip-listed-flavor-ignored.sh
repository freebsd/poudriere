FLAVOR_DEFAULT_ALL=no

LISTPORTS="misc/foo-FLAVORS-unsorted@ignored"
OVERLAYS="overlay omnibus"
. common.bulk.sh

do_bulk -n ${LISTPORTS}
assert 0 $? "Bulk should pass"

# Nothing fancy.
EXPECTED_IGNORED="misc/foo-FLAVORS-unsorted@ignored"
EXPECTED_SKIPPED=
EXPECTED_QUEUED=""
EXPECTED_LISTED="misc/foo-FLAVORS-unsorted@ignored"

assert_bulk_queue_and_stats
