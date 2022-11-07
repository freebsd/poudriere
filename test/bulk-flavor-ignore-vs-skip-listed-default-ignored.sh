FLAVOR_DEFAULT_ALL=no

LISTPORTS="misc/foo-default-IGNORED@DEFAULT"
# XXX: Adding this is because the framework gets very confused otherwise.
# That is, why are we actually queueing the skipped listed port? It's
# skipped early.
LISTPORTS="${LISTPORTS} ports-mgmt/pkg"
OVERLAYS="overlay omnibus"
. common.bulk.sh

do_bulk -n ${LISTPORTS}
assert 0 $? "Bulk should pass"

EXPECTED_LISTPORTS_IGNORED="misc/foo-default-IGNORED@DEFAULT"
EXPECTED_IGNORED="misc/foo-default-IGNORED@DEFAULT"
EXPECTED_SKIPPED=

assert_bulk_queue_and_stats
