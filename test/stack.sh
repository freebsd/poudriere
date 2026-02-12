set -e
. ./common.sh
set +e

STACK=
assert "0" "$(stack_size STACK)"
assert_ret 0 stack_push STACK "01 TT"
size=
assert_true stack_size STACK size
assert "1" "${size}"
assert_stack STACK "01 TT"
pop=
assert_ret 0 stack_pop STACK pop
assert "01 TT" "${pop:-}"
assert "0" "$(stack_size STACK)"
assert_stack STACK ""

STACK=
assert "0" "$(stack_size STACK)"
assert_ret 0 stack_push STACK "01 TT"
assert "1" "$(stack_size STACK)"
assert_stack STACK "01 TT"
assert_ret 0 stack_push STACK "02 QQ"
assert "2" "$(stack_size STACK)"
assert_stack STACK "02 QQ${STACK_SEP}01 TT"
assert "2" "$(stack_size STACK)"
assert_true assert_out 0 '02 QQ%01 TT$' stack_expand STACK %
assert_true assert_out 0 '02 QQ%01 TT$' stack_expand_front STACK %
assert_true assert_out 0 '01 TT%02 QQ$' stack_expand_back STACK %
assert_true assert_out 0 '02 QQ$'$'\n''01 TT$' stack_expand STACK $'\n'
assert_true assert_out 0 '02 QQ$'$'\n''01 TT$' stack_expand_front STACK $'\n'
assert_true assert_out 0 '01 TT$'$'\n''02 QQ$' stack_expand_back STACK $'\n'
assert_true assert_out 0 '02 QQ'$'\008''01 TT$' stack_expand STACK $'\008'
assert_true assert_out 0 '02 QQ'$'\008''01 TT$' stack_expand_front STACK $'\008'
assert_true assert_out 0 '01 TT'$'\008''02 QQ$' stack_expand_back STACK $'\008'

assert_true assert_out 0 '02 QQXRW01 TT$' stack_expand STACK XRW
assert_true assert_out 0 '02 QQXRW01 TT$' stack_expand_front STACK XRW
assert_true assert_out 0 '01 TTXRW02 QQ$' stack_expand_back STACK XRW

{
	output=
	assert_true stack_expand STACK $'\n' output
	assert '02 QQ'$'\n''01 TT' "${output}"

	output=
	assert_true stack_expand_front STACK $'\n' output
	assert '02 QQ'$'\n''01 TT' "${output}"

	output=
	assert_true stack_expand_back STACK $'\n' output
	assert '01 TT'$'\n''02 QQ' "${output}"

	assert_stack STACK "02 QQ${STACK_SEP}01 TT"
	assert_ret 0 stack_pop STACK pop
	assert "1" "$(stack_size STACK)"
	assert_stack STACK "01 TT"
	assert "${pop}" "02 QQ" "stack_pop"
	assert_ret 0 stack_pop STACK pop
	assert_stack STACK ""
	assert "0" "$(stack_size STACK)"
	assert "${pop}" "01 TT" "stack_pop"
	assert_ret_not 0 stack_pop STACK pop
	assert "" "${pop}"
}

{
	assert_stack STACK ""
	output=
	assert_false stack_expand STACK $'\n' output
	assert "" "${output}"
}

{
	assert_true stack_set STACK $'\n' '02 QQ'$'\n''01 TT'
	assert_stack STACK "02 QQ${STACK_SEP}01 TT"
	assert "2" "$(stack_size STACK)"
	assert_out 0 '02 QQ$'$'\n''01 TT$' stack_expand STACK $'\n'
}

{
	assert_true stack_set STACK $'\n' '02 QQ'$'\n''01 TT'
	assert_stack STACK "02 QQ${STACK_SEP}01 TT"
	assert "2" "$(stack_size STACK)"
	assert_out 0 '02 QQ$'$'\n''01 TT$' stack_expand STACK $'\n'
}

{
	tmp=$(mktemp -u)
	assert_true stack_expand STACK $'\n' > "${tmp}"
	assert_file - "${tmp}" <<-EOF
	02 QQ
	01 TT
	EOF
	rm -f "${tmp}"
}

{
	STACK=
	assert_stack STACK ""
	assert_true stack_set_args STACK '02 QQ' '01 TT'
	assert "2" "$(stack_size STACK)"
	assert_stack STACK "02 QQ${STACK_SEP}01 TT"
	assert_out 0 '02 QQ$'$'\n''01 TT$' stack_expand STACK $'\n'
}

{
	tmp=$(mktemp -u)
	cat > "${tmp}" <<-EOF
	1 5
	2 6
	3 7
	4 8
	EOF
	STACK=
	assert_stack STACK ""
	assert_true stack_set STACK $'\n' "$(cat "${tmp}")"
	assert "4" "$(stack_size STACK)"
	assert_true stack_isset STACK
	n=1
	item=
	while stack_pop STACK item; do
		assert "${n} $((n + 4))" "${item}"
		n=$((n + 1))
	done
	assert "5" "${n}"
	rm -f "${tmp}"
}

{
	STACK=
	assert_stack STACK ""
	assert_true stack_set_args STACK "1 5" "2 6" "3 7" "4 8"
	assert "4" "$(stack_size STACK)"
	assert_true stack_isset STACK
	n=1
	item=
	while stack_pop STACK item; do
		assert "${n} $((n + 4))" "${item}"
		n=$((n + 1))
	done
	assert "0" "$(stack_size STACK)"
	assert_false stack_isset STACK
	assert "5" "${n}"
	rm -f "${tmp}"
}

{
	assert_true stack_unset stack
	n=0
	max=10
	until [ "$n" -eq "$max" ]; do
		assert_ret 0 stack_push_back stack "${n}"
		n=$((n + 1))
	done
	assert_stack stack "0${STACK_SEP}1${STACK_SEP}2${STACK_SEP}3${STACK_SEP}4${STACK_SEP}5${STACK_SEP}6${STACK_SEP}7${STACK_SEP}8${STACK_SEP}9"
	assert "10" "$(stack_size stack)"
	assert_true stack_isset stack
}

{
	assert_true stack_unset stack
	assert "0" "$(stack_size stack)"
	assert_false stack_isset stack
	n=0
	max=10
	until [ "$n" -eq "$max" ]; do
		assert_ret 0 stack_push stack "${n} $((n + 2))"
		n=$((n + 1))
	done
	assert_stack stack "9 11${STACK_SEP}8 10${STACK_SEP}7 9${STACK_SEP}6 8${STACK_SEP}5 7${STACK_SEP}4 6${STACK_SEP}3 5${STACK_SEP}2 4${STACK_SEP}1 3${STACK_SEP}0 2"
	assert "10" "$(stack_size stack)"
	assert_true stack_isset stack
	n=$((max - 1))
	while stack_pop stack val; do
		assert "${n} $((n + 2))" "${val}"
		n=$((n - 1))
	done
	assert "-1" "${n}"
	assert "null" "${stack-null}"
	assert "0" "$(stack_size stack)"
	assert_false stack_isset stack
}

{
	assert_true stack_unset stack
	assert "0" "$(stack_size stack)"
	assert_false stack_isset stack
	n=0
	max=10
	until [ "$n" -eq "$max" ]; do
		assert_ret 0 stack_push stack "${n} $((n + 2))"
		n=$((n + 1))
	done
	assert "10" "$(stack_size stack)"
	assert_true stack_isset stack
	assert_stack stack "9 11${STACK_SEP}8 10${STACK_SEP}7 9${STACK_SEP}6 8${STACK_SEP}5 7${STACK_SEP}4 6${STACK_SEP}3 5${STACK_SEP}2 4${STACK_SEP}1 3${STACK_SEP}0 2"
	n=$((max - 1))
	unset tmp
	while stack_foreach stack val tmp; do
		assert "${n} $((n + 2))" "${val}"
		n=$((n - 1))
	done
	assert "-1" "${n}"
	assert_stack stack "9 11${STACK_SEP}8 10${STACK_SEP}7 9${STACK_SEP}6 8${STACK_SEP}5 7${STACK_SEP}4 6${STACK_SEP}3 5${STACK_SEP}2 4${STACK_SEP}1 3${STACK_SEP}0 2"
	n=$((max - 1))
	assert "10" "$(stack_size stack)"
	assert_true stack_isset stack
	unset tmp
	while stack_foreach stack val tmp; do
		assert "${n} $((n + 2))" "${val}"
		n=$((n - 1))
	done
	assert "-1" "${n}"
	assert_stack stack "9 11${STACK_SEP}8 10${STACK_SEP}7 9${STACK_SEP}6 8${STACK_SEP}5 7${STACK_SEP}4 6${STACK_SEP}3 5${STACK_SEP}2 4${STACK_SEP}1 3${STACK_SEP}0 2"
	assert "10" "$(stack_size stack)"
	assert_true stack_isset stack
}

{
	assert_true stack_unset stack
	assert_false stack_isset stack
	n=0
	max=10
	until [ "$n" -eq "$max" ]; do
		assert_ret 0 stack_push stack "${n} $((n + 2))"
		n=$((n + 1))
	done
	assert_stack stack "9 11${STACK_SEP}8 10${STACK_SEP}7 9${STACK_SEP}6 8${STACK_SEP}5 7${STACK_SEP}4 6${STACK_SEP}3 5${STACK_SEP}2 4${STACK_SEP}1 3${STACK_SEP}0 2"
	n=0
	assert_true stack_isset stack
	while stack_pop_back stack val; do
		assert "${n} $((n + 2))" "${val}"
		n=$((n + 1))
	done
	assert "${max}" "${n}"
	assert "null" "${stack-null}"
	assert_false stack_isset stack
}

{
	assert_true stack_unset stack
	n=0
	max=10
	until [ "$n" -eq "$max" ]; do
		assert_ret 0 stack_push stack "${n} $((n + 2))"
		n=$((n + 1))
	done
	assert_stack stack "9 11${STACK_SEP}8 10${STACK_SEP}7 9${STACK_SEP}6 8${STACK_SEP}5 7${STACK_SEP}4 6${STACK_SEP}3 5${STACK_SEP}2 4${STACK_SEP}1 3${STACK_SEP}0 2"
	n=0
	unset tmp
	while stack_foreach_back stack val tmp; do
		assert "${n} $((n + 2))" "${val}"
		n=$((n + 1))
	done
	assert "${max}" "${n}"
	assert_stack stack "9 11${STACK_SEP}8 10${STACK_SEP}7 9${STACK_SEP}6 8${STACK_SEP}5 7${STACK_SEP}4 6${STACK_SEP}3 5${STACK_SEP}2 4${STACK_SEP}1 3${STACK_SEP}0 2"
	n=0
	unset tmp
	while stack_foreach_back stack val tmp; do
		assert "${n} $((n + 2))" "${val}"
		n=$((n + 1))
	done
	assert "${max}" "${n}"
	assert_stack stack "9 11${STACK_SEP}8 10${STACK_SEP}7 9${STACK_SEP}6 8${STACK_SEP}5 7${STACK_SEP}4 6${STACK_SEP}3 5${STACK_SEP}2 4${STACK_SEP}1 3${STACK_SEP}0 2"
}

{
	assert_ret_not 0 isset tmp
	assert_ret_not 0 isset empty_stack
	assert_false stack_isset empty_stack
	assert_ret 1 stack_foreach_front empty_stack val tmp
}

{
	assert_ret_not 0 isset tmp
	assert_ret_not 0 isset empty_stack
	assert_false stack_isset empty_stack
	assert_ret 1 stack_foreach_back empty_stack val tmp
}
