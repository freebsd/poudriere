set -e
. ./common.sh
set +e

# Positive tests
{
	FOO=1
	assert_true catch_err required_env tests FOO '1'
	assert 0 "${CAUGHT_ERR_STATUS:-0}"
	assert "" "${CAUGHT_ERR_MSG-}"
	assert_false catch_err required_env tests FOO 're__null'
	assert_not 0 "${CAUGHT_ERR_STATUS:-0}"
	assert_case "*entered tests() with wrong environment:"$'\n'$'\t'"expected FOO = 're__null' actual: '1'" "${CAUGHT_ERR_MSG-}"
	FOO=
	assert_false catch_err required_env tests FOO '1'
	assert_not 0 "${CAUGHT_ERR_STATUS:-0}"
	assert_case "*entered tests() with wrong environment:"$'\n'$'\t'"expected FOO = '1' actual: ''" "${CAUGHT_ERR_MSG-}"
	assert_true catch_err required_env tests FOO ''
	assert 0 "${CAUGHT_ERR_STATUS:-0}"
	assert "" "${CAUGHT_ERR_MSG-}"
	assert_false catch_err required_env tests FOO 're__null'
	assert_not 0 "${CAUGHT_ERR_STATUS:-0}"
	assert_case "*entered tests() with wrong environment:"$'\n'$'\t'"expected FOO = 're__null' actual: ''" "${CAUGHT_ERR_MSG-}"
	unset FOO
	assert_false catch_err required_env tests FOO '1'
	assert_not 0 "${CAUGHT_ERR_STATUS:-0}"
	assert_case "*entered tests() with wrong environment:"$'\n'$'\t'"expected FOO = '1' actual: 're__null'" "${CAUGHT_ERR_MSG-}"
	assert_false catch_err required_env tests FOO ''
	assert_not 0 "${CAUGHT_ERR_STATUS:-0}"
	assert_case "*entered tests() with wrong environment:"$'\n'$'\t'"expected FOO = '' actual: 're__null'" "${CAUGHT_ERR_MSG-}"
	assert_true catch_err required_env tests FOO 're__null'
	assert 0 "${CAUGHT_ERR_STATUS:-0}"
	assert "" "${CAUGHT_ERR_MSG-}"
}

# Negative tests
{
	FOO=1
	assert_false catch_err required_env tests FOO'!' '1'
	assert_not 0 "${CAUGHT_ERR_STATUS:-0}"
	assert_case "*entered tests() with wrong environment:"$'\n'$'\t'"expected FOO != '1' actual: '1'" "${CAUGHT_ERR_MSG-}"
	assert_true catch_err required_env tests FOO'!' ''
	assert 0 "${CAUGHT_ERR_STATUS:-0}"
	assert "" "${CAUGHT_ERR_MSG-}"
	assert_true catch_err required_env tests FOO'!' 're__null'
	assert 0 "${CAUGHT_ERR_STATUS:-0}"
	assert "" "${CAUGHT_ERR_MSG-}"
	FOO=
	assert_true catch_err required_env tests FOO'!' '1'
	assert 0 "${CAUGHT_ERR_STATUS:-0}"
	assert "" "${CAUGHT_ERR_MSG-}"
	assert_false catch_err required_env tests FOO'!' ''
	assert_not 0 "${CAUGHT_ERR_STATUS:-0}"
	assert_case "*entered tests() with wrong environment:"$'\n'$'\t'"expected FOO != 'empty or re__null' actual: ''" "${CAUGHT_ERR_MSG-}"
	assert_true catch_err required_env tests FOO'!' 're__null'
	assert 0 "${CAUGHT_ERR_STATUS:-0}"
	assert "" "${CAUGHT_ERR_MSG-}"
	unset FOO
	assert_true catch_err required_env tests FOO'!' '1'
	assert 0 "${CAUGHT_ERR_STATUS:-0}"
	assert "" "${CAUGHT_ERR_MSG-}"
	assert_false catch_err required_env tests FOO'!' ''
	assert_not 0 "${CAUGHT_ERR_STATUS:-0}"
	assert_case "*entered tests() with wrong environment:"$'\n'$'\t'"expected FOO != 'empty or re__null' actual: 're__null'" "${CAUGHT_ERR_MSG-}"
	assert_false catch_err required_env tests FOO'!' 're__null'
	assert_not 0 "${CAUGHT_ERR_STATUS:-0}"
	assert_case "*entered tests() with wrong environment:"$'\n'$'\t'"expected FOO != 're__null' actual: 're__null'" "${CAUGHT_ERR_MSG-}"

	FOO=1
	BAR=1
	assert_true catch_err required_env tests FOO'!' '0' BAR '1'
	assert 0 "${CAUGHT_ERR_STATUS:-0}"
	assert "" "${CAUGHT_ERR_MSG-}"
	FOO=0
	BAR=0
	assert_true catch_err required_env tests FOO '0' BAR'!' '1'
	assert 0 "${CAUGHT_ERR_STATUS:-0}"
	assert "" "${CAUGHT_ERR_MSG-}"
}

# Same as above but done to ensure ! is symmetrical.
{
	for n in 0 "${EX_SOFTWARE}"; do
		if [ "$n" -ne 0 ]; then
			not='!'
		fi
		FOO=1
		assert_ret $n catch_err required_env tests FOO${not} '1'
		assert_ret_not $n catch_err required_env tests FOO${not} ''
		assert_ret_not $n catch_err required_env tests FOO${not} 're__null'
		FOO=
		assert_ret_not $n catch_err required_env tests FOO${not} '1'
		assert_ret $n catch_err required_env tests FOO${not} ''
		assert_ret_not $n catch_err required_env tests FOO${not} 're__null'
		unset FOO
		assert_ret_not $n catch_err required_env tests FOO${not} '1'
		assert_false catch_err required_env tests FOO${not} ''
		assert_ret $n catch_err required_env tests FOO${not} 're__null'
	done
}
