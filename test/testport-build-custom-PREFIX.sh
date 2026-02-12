OVERLAYS="omnibus"
TESTPORT="misc/foo"
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
do_testport -P -n ${TESTPORT}
assert 0 "$?" "testport dry-run should pass"
assert_bulk_queue_and_stats
assert_bulk_build_results
echo "-----" | tee /dev/stderr

EXPECTED_BUILT="${EXPECTED_TOBUILD}"
EXPECTED_FAILED=""
do_testport -P ${TESTPORT}
assert 0 "$?" "testport should pass"
assert_bulk_queue_and_stats
assert_bulk_build_results
echo "-----" | tee /dev/stderr

_log_path log || err 99 "Unable to determine logdir"

# pkg should get PREFIX=LOCALBASE
assert_true [ -e "${log:?}/logs/built/pkg-"*.log ]
set_pipefail
assert_true grep -w PREFIX= "${log:?}/logs/built/pkg-"*.log |
    tail -n 1 |
    grep -w "PREFIX=/usr/local"
assert 0 "$?" "testport PREFIX should match /usr/local"

# foo should get PREFIX != LOCALBASE
assert_true [ -e "${log:?}/logs/built/foo-"*.log ]
set_pipefail
assert_true grep -w PREFIX= "${log:?}/logs/built/foo-"*.log |
    tail -n 1 |
    grep "PREFIX=/prefix-"
assert 0 "$?" "testport PREFIX should match /prefix-*"
