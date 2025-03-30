FLAVOR_DEFAULT_ALL=no
FLAVOR_DEFAULT=-

LISTPORTS="misc/foo-FLAVORS-unsorted@${FLAVOR_DEFAULT}"
OVERLAYS="overlay omnibus"
. ./common.bulk.sh

do_bulk -c -n ${LISTPORTS}
assert 0 $? "Bulk should pass"

EXPECTED_IGNORED=
EXPECTED_SKIPPED=
EXPECTED_QUEUED="misc/foo-FLAVORS-unsorted@default misc/foo-dep-FLAVORS-unsorted@default ports-mgmt/pkg"
EXPECTED_LISTED="misc/foo-FLAVORS-unsorted@default"

assert_bulk_queue_and_stats
assert_bulk_dry_run
