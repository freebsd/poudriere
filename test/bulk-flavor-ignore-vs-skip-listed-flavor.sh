FLAVOR_DEFAULT_ALL=no

LISTPORTS="misc/foo-FLAVORS-unsorted@DEPIGNORED"
# XXX: Adding this is because the framework gets very confused otherwise.
# That is, why are we actually queueing the skipped listed port? It's
# skipped early.
LISTPORTS="${LISTPORTS} ports-mgmt/pkg"
OVERLAYS="overlay omnibus"
. common.bulk.sh

do_bulk -n ${LISTPORTS}
assert 0 $? "Bulk should pass"

# With misc/foo-FLAVORS-unsorted@DEPIGNORED we should get a skip
# on the listed port since we explicitly requested it. The dependency
# will be ignored and cause the listed to skip.
EXPECTED_IGNORED="misc/foo-dep-FLAVORS-unsorted@DEPIGNORED"
EXPECTED_SKIPPED="misc/foo-FLAVORS-unsorted@DEPIGNORED"

assert_bulk_queue_and_stats
