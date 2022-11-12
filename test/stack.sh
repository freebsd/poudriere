set -e
. common.sh
set +e

_assert_stack() {
	local lineinfo="$1"
	local stack_var="$2"
	local expected="$3"
	local reason="$4"
	local have_tmp=$(mktemp -t assert_stack)
	local expected_tmp=$(mktemp -t assert_stack)
	local ret=0
        local val

        val="$(getvar "${stack_var}")"
	echo "${val}" | tr ' ' '\n' | sort | sed -e '/^$/d' > "${have_tmp}"
	echo "${expected}" | tr ' ' '\n' | sort | sed -e '/^$/d' > \
	    "${expected_tmp}"
	cmp -s "${have_tmp}" "${expected_tmp}" || ret=$?
	[ ${ret} -ne 0 ] && comm "${have_tmp}" "${expected_tmp}" >&2

	rm -f "${have_tmp}" "${expected_tmp}"
	_assert "${lineinfo}" 0 "${ret}" \
		"${reason} - Have: '${val}' Expected: '${expected}'"
}
alias assert_stack='_assert_stack "$0:$LINENO"'

STACK=
assert_ret 0 stack_push STACK "01"
assert_stack STACK "01"
assert_ret 0 stack_push STACK "02"
assert_stack STACK "02 01"
assert_ret 0 stack_pop STACK pop
assert_stack STACK "01"
assert "${pop}" "02" "stack_pop"
assert_ret 0 stack_pop STACK pop
assert_stack STACK ""
assert "${pop}" "01" "stack_pop"
assert_ret_not 0 stack_pop STACK pop
assert "" "${pop}"

{
	stack=
	n=0
	max=10
	until [ "$n" -eq "$max" ]; do
		assert_ret 0 stack_push_back stack "${n}"
		n=$((n + 1))
	done
	assert_stack stack "0 1 2 3 4 5 6 7 8 9"
}

{
	stack=
	n=0
	max=10
	until [ "$n" -eq "$max" ]; do
		assert_ret 0 stack_push stack "${n}"
		n=$((n + 1))
	done
	assert_stack stack "9 8 7 6 5 4 3 2 1 0"
	n=$((max - 1))
	while stack_pop stack val; do
		assert "${n}" "${val}"
		n=$((n - 1))
	done
	assert "-1" "${n}"
	assert "null" "${stack-null}"
}

{
	stack=
	n=0
	max=10
	until [ "$n" -eq "$max" ]; do
		assert_ret 0 stack_push stack "${n}"
		n=$((n + 1))
	done
	assert_stack stack "9 8 7 6 5 4 3 2 1 0"
	n=$((max - 1))
	while stack_foreach stack val tmp; do
		assert "${n}" "${val}"
		n=$((n - 1))
	done
	assert "-1" "${n}"
	assert_stack stack "9 8 7 6 5 4 3 2 1 0"
	n=$((max - 1))
	while stack_foreach stack val tmp; do
		assert "${n}" "${val}"
		n=$((n - 1))
	done
	assert "-1" "${n}"
	assert_stack stack "9 8 7 6 5 4 3 2 1 0"
}

{
	stack=
	n=0
	max=10
	until [ "$n" -eq "$max" ]; do
		assert_ret 0 stack_push stack "${n}"
		n=$((n + 1))
	done
	assert_stack stack "9 8 7 6 5 4 3 2 1 0"
	n=0
	while stack_pop_back stack val; do
		assert "${n}" "${val}"
		n=$((n + 1))
	done
	assert "${max}" "${n}"
	assert "null" "${stack-null}"
}

{
	stack=
	n=0
	max=10
	until [ "$n" -eq "$max" ]; do
		assert_ret 0 stack_push stack "${n}"
		n=$((n + 1))
	done
	assert_stack stack "9 8 7 6 5 4 3 2 1 0"
	n=0
	while stack_foreach_back stack val tmp; do
		assert "${n}" "${val}"
		n=$((n + 1))
	done
	assert "${max}" "${n}"
	assert_stack stack "9 8 7 6 5 4 3 2 1 0"
	n=0
	while stack_foreach_back stack val tmp; do
		assert "${n}" "${val}"
		n=$((n + 1))
	done
	assert "${max}" "${n}"
	assert_stack stack "9 8 7 6 5 4 3 2 1 0"
}

{
	assert_ret_not 0 issetvar tmp
	assert_ret_not 0 issetvar empty_stack
	assert_ret 1 stack_foreach_front empty_stack val tmp
}

{
	assert_ret_not 0 issetvar tmp
	assert_ret_not 0 issetvar empty_stack
	assert_ret 1 stack_foreach_back empty_stack val tmp
}
