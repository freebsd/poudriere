TESTPORT="misc/foo@broken"
OVERLAYS="omnibus"
LISTPORTS="${TESTPORT}"
. ./common.bulk.sh

# testport will keep old packages so we need to clean out everything
# before doing the first run to ensure it all builds.
do_pkgclean -y -A
assert 0 $? "Pkgclean should pass"
echo "-----" | tee /dev/stderr

EXPECTED_QUEUED="ports-mgmt/pkg ${TESTPORT}"
EXPECTED_LISTED="${TESTPORT}"
EXPECTED_TOBUILD="${EXPECTED_QUEUED}"
EXPECTED_IGNORED=
EXPECTED_BUILT=
do_testport -n ${TESTPORT}
assert 0 "$?" "testport dry-run should pass"
assert_bulk_queue_and_stats
assert_bulk_build_results
echo "-----" | tee /dev/stderr

EXPECTED_BUILT="${EXPECTED_TOBUILD}"
do_testport ${TESTPORT}
assert 0 "$?" "testport should pass"
assert_bulk_queue_and_stats
assert_bulk_build_results
echo "-----" | tee /dev/stderr
