OVERLAYS=omnibus
FLAVOR_ALL=all
TESTPORT="misc/freebsd-release-manifests@badflavor"
LISTPORTS="${TESTPORT}"
. ./common.bulk.sh

EXPECTED_QUEUED=
EXPECTED_LISTED=
EXPECTED_TOBUILD=
EXPECTED_BUILT=
do_testport -n ${TESTPORT}
assert 1 "$?" "testport dry-run for bad flavor should fail"
assert_bulk_queue_and_stats
assert_bulk_build_results

do_testport ${TESTPORT}
assert 1 "$?" "testport dry-run for bad flavor should fail"
assert_bulk_queue_and_stats
assert_bulk_build_results
