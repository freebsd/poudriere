set -e
. common.sh
set +e

# Positive tests
{
	FOO=1
	assert_true required_env tests FOO '1'
	assert_false required_env tests FOO ''
	assert_false required_env tests FOO 're__null'
	FOO=
	assert_false required_env tests FOO '1'
	assert_true required_env tests FOO ''
	assert_false required_env tests FOO 're__null'
	unset FOO
	assert_false required_env tests FOO '1'
	assert_false required_env tests FOO ''
	assert_true required_env tests FOO 're__null'
}

# Negative tests
{
	FOO=1
	assert_false required_env tests FOO'!' '1'
	assert_true required_env tests FOO'!' ''
	assert_true required_env tests FOO'!' 're__null'
	FOO=
	assert_true required_env tests FOO'!' '1'
	assert_false required_env tests FOO'!' ''
	assert_true required_env tests FOO'!' 're__null'
	unset FOO
	assert_true required_env tests FOO'!' '1'
	assert_false required_env tests FOO'!' ''
	assert_false required_env tests FOO'!' 're__null'

	FOO=1
	BAR=1
	assert_true required_env tests FOO'!' '0' BAR '1'
	FOO=0
	BAR=0
	assert_true required_env tests FOO '0' BAR'!' '1'
}

# Same as above but done to ensure ! is symmetrical.
{
	for n in 0 1; do
		if [ "$n" -eq 1 ]; then
			not='!'
		fi
		FOO=1
		assert_ret $n required_env tests FOO${not} '1'
		assert_ret_not $n required_env tests FOO${not} ''
		assert_ret_not $n required_env tests FOO${not} 're__null'
		FOO=
		assert_ret_not $n required_env tests FOO${not} '1'
		assert_ret $n required_env tests FOO${not} ''
		assert_ret_not $n required_env tests FOO${not} 're__null'
		unset FOO
		assert_ret_not $n required_env tests FOO${not} '1'
		assert_false required_env tests FOO${not} ''
		assert_ret $n required_env tests FOO${not} 're__null'
	done
}
