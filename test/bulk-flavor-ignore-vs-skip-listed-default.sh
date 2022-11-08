FLAVOR_DEFAULT_ALL=no
FLAVOR_DEFAULT=-

LISTPORTS="misc/foo-FLAVORS-unsorted@${FLAVOR_DEFAULT}"
OVERLAYS="overlay omnibus"
. common.bulk.sh

do_bulk -n ${LISTPORTS}
assert 0 $? "Bulk should pass"

EXPECTED_IGNORED=
EXPECTED_SKIPPED=
EXPECTED_QUEUED="misc/foo-FLAVORS-unsorted misc/foo-dep-FLAVORS-unsorted ports-mgmt/pkg"
EXPECTED_LISTED="misc/foo-FLAVORS-unsorted"

assert_bulk_queue_and_stats
