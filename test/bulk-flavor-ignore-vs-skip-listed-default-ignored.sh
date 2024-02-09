FLAVOR_DEFAULT_ALL=no

LISTPORTS="misc/foo-default-IGNORED@default"
OVERLAYS="overlay omnibus"
. common.bulk.sh

do_bulk -n ${LISTPORTS}
assert 0 $? "Bulk should pass"

EXPECTED_IGNORED="misc/foo-default-IGNORED@default"
EXPECTED_SKIPPED=
EXPECTED_TOBUILD=
EXPECTED_QUEUED="misc/foo-default-IGNORED@default"
EXPECTED_LISTED="misc/foo-default-IGNORED@default"

assert_bulk_queue_and_stats
