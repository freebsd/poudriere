OVERLAYS=omnibus
FLAVOR_ALL=all
LISTPORTS="misc/freebsd-release-manifests@badflavor"
. ./common.bulk.sh

EXPECTED_QUEUED=
EXPECTED_LISTED=
EXPECTED_TOBUILD=
EXPECTED_BUILT=
do_bulk -cn -d ${LISTPORTS}
assert 0 "$?" "bulk dry-run for bad flavor should not fail with -d"
assert_bulk_queue_and_stats
assert_bulk_build_results

do_bulk -cn -D ${LISTPORTS}
assert 1 "$?" "bulk dry-run for bad flavor should fail with -D"
assert_bulk_queue_and_stats
assert_bulk_build_results

do_bulk -c -d ${LISTPORTS}
assert 0 "$?" "bulk dry-run for bad flavor should not fail with -d"
assert_bulk_queue_and_stats
assert_bulk_build_results

do_bulk -c -D ${LISTPORTS}
assert 1 "$?" "bulk dry-run for bad flavor should fail with -D"
assert_bulk_queue_and_stats
assert_bulk_build_results
