set -e
. common.sh
set +e

STACK=
assert_ret 0 stack_push STACK "01"
assert_stack STACK "01"
assert_ret 0 stack_push STACK "02"
assert_stack STACK "02${STACK_SEP}01"
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
	assert_stack stack "0${STACK_SEP}1${STACK_SEP}2${STACK_SEP}3${STACK_SEP}4${STACK_SEP}5${STACK_SEP}6${STACK_SEP}7${STACK_SEP}8${STACK_SEP}9"
}

{
	stack=
	n=0
	max=10
	until [ "$n" -eq "$max" ]; do
		assert_ret 0 stack_push stack "${n} $((n + 2))"
		n=$((n + 1))
	done
	assert_stack stack "9 11${STACK_SEP}8 10${STACK_SEP}7 9${STACK_SEP}6 8${STACK_SEP}5 7${STACK_SEP}4 6${STACK_SEP}3 5${STACK_SEP}2 4${STACK_SEP}1 3${STACK_SEP}0 2"
	n=$((max - 1))
	while stack_pop stack val; do
		assert "${n} $((n + 2))" "${val}"
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
		assert_ret 0 stack_push stack "${n} $((n + 2))"
		n=$((n + 1))
	done
	assert_stack stack "9 11${STACK_SEP}8 10${STACK_SEP}7 9${STACK_SEP}6 8${STACK_SEP}5 7${STACK_SEP}4 6${STACK_SEP}3 5${STACK_SEP}2 4${STACK_SEP}1 3${STACK_SEP}0 2"
	n=$((max - 1))
	while stack_foreach stack val tmp; do
		assert "${n} $((n + 2))" "${val}"
		n=$((n - 1))
	done
	assert "-1" "${n}"
	assert_stack stack "9 11${STACK_SEP}8 10${STACK_SEP}7 9${STACK_SEP}6 8${STACK_SEP}5 7${STACK_SEP}4 6${STACK_SEP}3 5${STACK_SEP}2 4${STACK_SEP}1 3${STACK_SEP}0 2"
	n=$((max - 1))
	while stack_foreach stack val tmp; do
		assert "${n} $((n + 2))" "${val}"
		n=$((n - 1))
	done
	assert "-1" "${n}"
	assert_stack stack "9 11${STACK_SEP}8 10${STACK_SEP}7 9${STACK_SEP}6 8${STACK_SEP}5 7${STACK_SEP}4 6${STACK_SEP}3 5${STACK_SEP}2 4${STACK_SEP}1 3${STACK_SEP}0 2"
}

{
	stack=
	n=0
	max=10
	until [ "$n" -eq "$max" ]; do
		assert_ret 0 stack_push stack "${n} $((n + 2))"
		n=$((n + 1))
	done
	assert_stack stack "9 11${STACK_SEP}8 10${STACK_SEP}7 9${STACK_SEP}6 8${STACK_SEP}5 7${STACK_SEP}4 6${STACK_SEP}3 5${STACK_SEP}2 4${STACK_SEP}1 3${STACK_SEP}0 2"
	n=0
	while stack_pop_back stack val; do
		assert "${n} $((n + 2))" "${val}"
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
		assert_ret 0 stack_push stack "${n} $((n + 2))"
		n=$((n + 1))
	done
	assert_stack stack "9 11${STACK_SEP}8 10${STACK_SEP}7 9${STACK_SEP}6 8${STACK_SEP}5 7${STACK_SEP}4 6${STACK_SEP}3 5${STACK_SEP}2 4${STACK_SEP}1 3${STACK_SEP}0 2"
	n=0
	while stack_foreach_back stack val tmp; do
		assert "${n} $((n + 2))" "${val}"
		n=$((n + 1))
	done
	assert "${max}" "${n}"
	assert_stack stack "9 11${STACK_SEP}8 10${STACK_SEP}7 9${STACK_SEP}6 8${STACK_SEP}5 7${STACK_SEP}4 6${STACK_SEP}3 5${STACK_SEP}2 4${STACK_SEP}1 3${STACK_SEP}0 2"
	n=0
	while stack_foreach_back stack val tmp; do
		assert "${n} $((n + 2))" "${val}"
		n=$((n + 1))
	done
	assert "${max}" "${n}"
	assert_stack stack "9 11${STACK_SEP}8 10${STACK_SEP}7 9${STACK_SEP}6 8${STACK_SEP}5 7${STACK_SEP}4 6${STACK_SEP}3 5${STACK_SEP}2 4${STACK_SEP}1 3${STACK_SEP}0 2"
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
