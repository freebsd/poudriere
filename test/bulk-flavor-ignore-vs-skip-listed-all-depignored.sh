FLAVOR_DEFAULT_ALL=no

# XXX: Removing DEFAULT here breaks the framework. It should default to the first flav due to FLAVOR_DEFAULT_ALL=no
LISTPORTS="misc/foo-all-DEPIGNORED@DEFAULT"
OVERLAYS="overlay omnibus"
. common.bulk.sh

do_bulk -n ${LISTPORTS}
assert 0 $? "Bulk should pass"

EXPECTED_IGNORED="misc/foo-dep-FLAVORS-unsorted@DEPIGNORED"
EXPECTED_SKIPPED="misc/foo-all-DEPIGNORED@DEFAULT"
EXPECTED_QUEUED="ports-mgmt/pkg"
EXPECTED_LISTED="misc/foo-all-DEPIGNORED"

assert_bulk_queue_and_stats
