FLAVOR_DEFAULT_ALL=no
FLAVOR_DEFAULT=-

LISTPORTS="misc/foo-default-DEPIGNORED@FLAV"
OVERLAYS="overlay omnibus"
. common.bulk.sh

do_bulk -n ${LISTPORTS}
assert 0 $? "Bulk should pass"

EXPECTED_IGNORED=
EXPECTED_SKIPPED=

assert_bulk_queue_and_stats
