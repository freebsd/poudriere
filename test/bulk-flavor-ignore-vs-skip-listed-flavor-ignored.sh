FLAVOR_DEFAULT_ALL=no

LISTPORTS="misc/foo-FLAVORS-unsorted@ignored"
OVERLAYS="overlay omnibus"
. ./common.bulk.sh

do_bulk -c -n ${LISTPORTS}
assert 0 $? "Bulk should pass"

# Nothing fancy.
EXPECTED_IGNORED="misc/foo-FLAVORS-unsorted@ignored"
EXPECTED_SKIPPED=
EXPECTED_TOBUILD=
EXPECTED_QUEUED="misc/foo-FLAVORS-unsorted@ignored"
EXPECTED_LISTED="misc/foo-FLAVORS-unsorted@ignored"

assert_bulk_queue_and_stats
assert_bulk_dry_run
