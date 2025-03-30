TEST_OVERRIDE_ERR=0
set -e
. ./common.sh
set +e

foo() {
	echo stdout
	err 9 eRROR
}

assert_ret 7 catch_err err 7 eRRoR
assert "null" "${CRASHED-null}"
assert 7 "${CAUGHT_ERR_STATUS-null}"
assert "core error" "${CAUGHT_ERR_MSG-null}"
unset CAUGHT_ERR_STATUS CAUGHT_ERR_MSG

# eval is needed because 'err' needs to be alias-expanded.
assert_ret 8 catch_err eval err 8 eRRor
assert "null" "${CRASHED-null}"
assert 8 "${CAUGHT_ERR_STATUS}"
assert "core error" "${CAUGHT_ERR_MSG}"
unset CAUGHT_ERR_STATUS CAUGHT_ERR_MSG

assert_out 9 'stdout$' foo
# Only the test framework version of err() captures error like this
assert_false [ -e "${ERR_CHECK:?}" ]
assert "null" "${CRASHED-null}"
assert "null" "${CAUGHT_ERR_STATUS-null}"
