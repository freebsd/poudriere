FLAVOR_DEFAULT_ALL=no
FLAVOR_DEFAULT=-

LISTPORTS="misc/foo-all-DEPIGNORED@FLAV"
OVERLAYS="overlay omnibus"
. common.bulk.sh

do_bulk -n ${LISTPORTS}
assert 0 $? "Bulk should pass"

EXPECTED_IGNORED="misc/foo-dep-FLAVORS-unsorted@DEPIGNORED"
EXPECTED_SKIPPED="misc/foo-all-DEPIGNORED@FLAV"
EXPECTED_QUEUED="ports-mgmt/pkg"
EXPECTED_LISTED="misc/foo-all-DEPIGNORED@FLAV"

assert_bulk_queue_and_stats
