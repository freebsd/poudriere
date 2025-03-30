OVERLAYS="omnibus porttesting"
TESTPORT="ports-mgmt/poudriere-devel-porttesting"
LISTPORTS="${TESTPORT}"
. ./common.bulk.sh

# testport will keep old packages so we need to clean out everything
# before doing the first run to ensure it all builds.
do_pkgclean -y -A
assert 0 $? "Pkgclean should pass"
echo "-----" | tee /dev/stderr

EXPECTED_QUEUED="ports-mgmt/pkg ${TESTPORT}"
EXPECTED_LISTED="${TESTPORT}"
EXPECTED_TOBUILD="ports-mgmt/pkg ${TESTPORT}"
EXPECTED_BUILT=
do_testport -n ${TESTPORT}
assert 0 "$?" "testport dry-run should pass"
assert_bulk_queue_and_stats
assert_bulk_build_results
echo "-----" | tee /dev/stderr

EXPECTED_BUILT="ports-mgmt/pkg"
EXPECTED_FAILED="ports-mgmt/poudriere-devel-porttesting"
do_testport ${TESTPORT}
rssert 1 "$?" "testport should fail"
assert_bulk_queue_and_stats
assert_bulk_build_results
echo "-----" | tee /dev/stderr
