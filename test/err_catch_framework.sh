set -e
. common.sh
set +e

foo() {
	echo stdout
	err 9 eRROR
}

# eval is needed because 'err' needs to be alias-expanded.
assert_ret 8 catch_err eval err 8 eRRor
assert "null" "${CRASHED-null}"
assert 8 "${CAUGHT_ERR_STATUS:?}"
assert_case "*eRRor" "${CAUGHT_ERR_MSG}"
unset CAUGHT_ERR_STATUS CAUGHT_ERR_MSG

# Framework always returns 99
assert_ret 99 eval assert_out 'stdout$' foo
assert "null" "${CRASHED-null}"
assert "null" "${CAUGHT_ERR_STATUS-null}"
