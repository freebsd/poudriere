# This test covers basic MOVED.
OVERLAYS="omnibus"
TESTPORT_MOVED="misc/freebsd-release-manifests-OLD-MOVED"
TESTPORT="misc/freebsd-release-manifests"
LISTPORTS="${TESTPORT}"
. ./common.bulk.sh

# testport will keep old packages so we need to clean out everything
# before doing the first run to ensure it all builds.
do_pkgclean -y -A
assert 0 $? "Pkgclean should pass"
echo "-----" | tee /dev/stderr

EXPECTED_QUEUED="ports-mgmt/pkg ${TESTPORT}:listed"
EXPECTED_LISTED="${TESTPORT}"
EXPECTED_TOBUILD="${EXPECTED_QUEUED}"
EXPECTED_BUILT=
do_testport -n ${TESTPORT_MOVED}
assert 0 "$?" "testport dry-run should pass"
assert_bulk_queue_and_stats
assert_bulk_build_results
echo "-----" | tee /dev/stderr

EXPECTED_BUILT="${EXPECTED_TOBUILD}"
do_testport ${TESTPORT_MOVED}
assert 0 "$?" "testport should pass"
assert_bulk_queue_and_stats
assert_bulk_build_results
echo "-----" | tee /dev/stderr

# Do it again and ensure no dependencies are built
EXPECTED_QUEUED="${TESTPORT}:listed"
EXPECTED_LISTED="${TESTPORT}"
EXPECTED_TOBUILD="${TESTPORT}"
EXPECTED_BUILT=
do_testport -n ${TESTPORT_MOVED}
assert 0 "$?" "testport dry-run should pass"
assert_bulk_queue_and_stats
assert_bulk_build_results
echo "-----" | tee /dev/stderr

EXPECTED_BUILT="${EXPECTED_TOBUILD}"
# Now we can run again and ensure we do not build anything except the
# test port.
do_testport ${TESTPORT_MOVED}
assert 0 "$?" "testport should pass"
assert_bulk_queue_and_stats
assert_bulk_build_results
echo "-----" | tee /dev/stderr
