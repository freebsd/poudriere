FLAVOR_DEFAULT_ALL=no

# XXX: Removing DEFAULT here breaks the framework. It should default to the first flav due to FLAVOR_DEFAULT_ALL=no
LISTPORTS="misc/foo-default-DEPIGNORED@DEFAULT"
# XXX: Adding this is because the framework gets very confused otherwise.
# That is, why are we actually queueing the skipped listed port? It's
# skipped early.
LISTPORTS="${LISTPORTS} ports-mgmt/pkg"
OVERLAYS="overlay omnibus"
. common.bulk.sh

do_bulk -n ${LISTPORTS}
assert 0 $? "Bulk should pass"

EXPECTED_IGNORED="misc/foo-dep-FLAVORS-unsorted@DEPIGNORED"
EXPECTED_SKIPPED="misc/foo-default-DEPIGNORED@DEFAULT"

assert_bulk_queue_and_stats
