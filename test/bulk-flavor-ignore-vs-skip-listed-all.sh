FLAVOR_DEFAULT_ALL=no
FLAVOR_ALL=all

LISTPORTS="misc/foo-FLAVORS-unsorted@${FLAVOR_ALL}"
OVERLAYS="overlay omnibus"
. common.bulk.sh

do_bulk -n ${LISTPORTS}
assert 0 $? "Bulk should pass"

# With misc/foo-FLAVORS-unsorted@all nothing should be skipped.
# Everything should just be ignored.
EXPECTED_IGNORED="misc/foo-FLAVORS-unsorted@IGNORED misc/foo-FLAVORS-unsorted@DEPIGNORED misc/foo-dep-FLAVORS-unsorted@DEPIGNORED"
EXPECTED_SKIPPED=

assert_bulk_queue_and_stats
