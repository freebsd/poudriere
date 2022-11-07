FLAVOR_DEFAULT_ALL=no
FLAVOR_DEFAULT=-

LISTPORTS="misc/foo-all-DEPIGNORED@FLAV"
# XXX: Adding this is because the framework gets very confused otherwise.
# That is, why are we actually queueing the skipped listed port? It's
# skipped early.
LISTPORTS="${LISTPORTS} ports-mgmt/pkg"
OVERLAYS="overlay omnibus"
. common.bulk.sh

do_bulk -n ${LISTPORTS}
assert 0 $? "Bulk should pass"

EXPECTED_IGNORED="misc/foo-dep-FLAVORS-unsorted@DEPIGNORED"
EXPECTED_SKIPPED="misc/foo-all-DEPIGNORED@FLAV"

assert_bulk_queue_and_stats
