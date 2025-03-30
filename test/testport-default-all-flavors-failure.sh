OVERLAYS=omnibus
FLAVOR_DEFAULT_ALL=yes
TESTPORT="misc/freebsd-release-manifests"
LISTPORTS="${TESTPORT}"
. ./common.bulk.sh

EXPECTED_QUEUED=
EXPECTED_LISTED=
EXPECTED_TOBUILD=
EXPECTED_BUILT=
do_testport -n ${TESTPORT}
assert 1 "$?" "testport dry-run for all flavors should fail"
# No logdir should exist
_log_path log || err 99 "Unable to determine logdir"
assert_false [ -e "${log}" ]

do_testport ${TESTPORT}
assert 1 "$?" "testport dry-run for all flavors should fail"
# No logdir should exist
_log_path log || err 99 "Unable to determine logdir"
assert_false [ -e "${log}" ]
