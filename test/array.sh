set -e
. ./common.sh
set +e

{
	assert_false array_isset ARRAY
	assert 0 "$(array_size ARRAY)"
	assert_true array_set ARRAY 0 "blah"
	assert_true array_isset ARRAY
	assert 1 "$(array_size ARRAY)"
	assert "blah" "$(array_get ARRAY 0)"
	assert_true array_set ARRAY 1 "foo"
	assert 2 "$(array_size ARRAY)"
	assert "blah" "$(array_get ARRAY 0)"
	assert "foo" "$(array_get ARRAY 1)"
	assert_true array_set ARRAY 0 "bar"
	assert 2 "$(array_size ARRAY)"
	assert "bar" "$(array_get ARRAY 0)"
	assert "foo" "$(array_get ARRAY 1)"
	assert_true array_set ARRAY 99 "baz"
	assert 3 "$(array_size ARRAY)"
	assert "bar" "$(array_get ARRAY 0)"
	assert "foo" "$(array_get ARRAY 1)"
	assert "baz" "$(array_get ARRAY 99)"
	assert_true array_unset ARRAY 0
	assert 2 "$(array_size ARRAY)"
	assert "foo" "$(array_get ARRAY 1)"
	assert "baz" "$(array_get ARRAY 99)"
	assert_true array_unset ARRAY
	assert_false array_isset ARRAY
	assert 0 "$(array_size ARRAY)"
	value=
	assert_false array_get ARRAY 0 value
	assert_false array_get ARRAY 1 value
	assert_false array_get ARRAY 99 value
}

{
	assert_true array_unset ARRAY
	assert_false array_isset ARRAY
	n=0
	max=10
	until [ "$n" -eq "$max" ]; do
		assert_true array_set ARRAY "${n}" "$((n * 2))"
		n="$((n + 1))"
	done
	size=
	assert_true array_size ARRAY size
	assert "${max}" "${size}"
	n=0
	while array_foreach ARRAY val tmp; do
		assert "$((n * 2))" "${val}"
		n="$((n + 1))"
	done
	assert "${max}" "${n}"
	assert_true array_isset ARRAY
	assert "${max}" "${size}"
	assert "${max}" "$(array_size ARRAY -)"
}

{
	assert_true array_unset ARRAY
	assert_false array_isset ARRAY
	n=0
	max=10
	until [ "$n" -eq "$max" ]; do
		assert_true array_push_back ARRAY "$((n * 2))"
		n="$((n + 1))"
	done
	size=
	assert_true array_size ARRAY size
	assert "${max}" "${size}"
	n="$((max - 1))"
	while array_pop_back ARRAY val; do
		assert "$((n * 2))" "${val}"
		n="$((n - 1))"
	done
	assert "-1" "${n}"
	assert "0" "$(array_size ARRAY "")"
}
