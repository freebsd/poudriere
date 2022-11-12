set -e
. common.sh
set +e

assert_ret 0 hash_push stack a 1
assert_ret 0 hash_isset stack a
assert_ret 0 hash_get stack a val
assert "1" "${val}" "hash_get stack a val"

assert_ret 0 hash_push stack a 2
assert_ret 0 hash_get stack a val
assert "2 1" "${val}" "hash_get stack a val"

assert_ret 0 hash_pop stack a val
assert "2" "${val}" "hash_pop stack a val"
assert_ret 0 hash_get stack a val
assert "1" "${val}" "hash_get stack a val"

assert_ret 0 hash_pop stack a val
assert "1" "${val}" "hash_pop stack a val"
assert_ret 0 hash_isset stack a
assert_ret 1 hash_pop stack a val
assert_ret 1 hash_isset stack a

{
	n=0
	max=10
	until [ "$n" -eq "$max" ]; do
		assert_ret 0 hash_push_back stack b "${n}"
		n=$((n + 1))
	done
	assert_ret 0 hash_get stack b val
	assert "0 1 2 3 4 5 6 7 8 9" "${val}"
	assert_ret 0 hash_unset stack b
}

{
	n=0
	max=10
	until [ "$n" -eq "$max" ]; do
		assert_ret 0 hash_push stack b "${n}"
		n=$((n + 1))
	done
	assert "10" "${n}"
	assert_ret 0 hash_get stack b val
	assert "9 8 7 6 5 4 3 2 1 0" "${val}"
	n=$((max - 1))
	while hash_foreach stack b val tmp; do
		assert "${n}" "${val}"
		n=$((n - 1))
	done
	assert "-1" "${n}"
	assert_ret 0 hash_get stack b val
	assert "9 8 7 6 5 4 3 2 1 0" "${val}"
	n=$((max - 1))
	while hash_pop stack b val; do
		assert "${n}" "${val}"
		n=$((n - 1))
	done
	assert "-1" "${n}"
	assert_ret_not 0 hash_isset stack b
}

{
	n=0
	max=10
	until [ "$n" -eq "$max" ]; do
		assert_ret 0 hash_push stack b "${n}"
		n=$((n + 1))
	done
	assert "10" "${n}"
	assert_ret 0 hash_get stack b val
	assert "9 8 7 6 5 4 3 2 1 0" "${val}"
	n=0
	while hash_foreach_back stack b val tmp; do
		assert "${n}" "${val}"
		n=$((n + 1))
	done
	assert "${max}" "${n}"
	assert_ret 0 hash_get stack b val
	assert "9 8 7 6 5 4 3 2 1 0" "${val}"
	n=0
	while hash_pop_back stack b val; do
		assert "${n}" "${val}"
		n=$((n + 1))
	done
	assert "${max}" "${n}"
	assert_ret_not 0 hash_isset stack b
}

exit 0
