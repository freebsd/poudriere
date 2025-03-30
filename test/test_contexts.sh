. ./common.sh

test_setup() {
	hash_set setup "${A:?}${B+bad}${C:?}" 1
}

test_teardown() {
	hash_unset setup "${A:?}${B+bad}${C:?}"
	hash_set teardown "${A:?}${B+bad}${C:?}" 1
}

set_test_contexts - test_setup test_teardown <<-EOF
A 1 2
#B 3 4
C 5 6
EOF

expected_combos=
case " ${TEST_NUMS-null} " in
" null ")
	expected_combos="15 16 25 26"
	;;
*" 1 "*) expected_combos="${expected_combos:+${expected_combos} }15" ;;
*" 2 "*) expected_combos="${expected_combos:+${expected_combos} }16" ;;
*" 3 "*) expected_combos="${expected_combos:+${expected_combos} }25" ;;
*" 4 "*) expected_combos="${expected_combos:+${expected_combos} }26" ;;
esac
for combo in ${expected_combos}; do
	assert_true hash_set got "${combo}" 0
done

n=0
while get_test_context; do
	if [ "$n" -gt 0 ]; then
		assert_true hash_get teardown "${CURITER}" value
		assert "1" "${value}" "Iteration A=$A B=$B C=$C -- after ${CURITER}"
	fi
	CURITER="${A:?}${B+bad}${C:?}"
	assert_true hash_get setup "${CURITER}" value
	assert "1" "${value}" "Iteration A=$A B=$B C=$C"
	assert_true hash_isset got "${CURITER}"
	value=
	assert_true hash_get got "${CURITER}" value
	assert "0" "${value}" "Iteration A=$A B=$B C=$C"
	assert_true hash_set got "${CURITER}" 1
	n=$((n + 1))
done
assert_true hash_get teardown "${CURITER}" value
assert "1" "${value}" "Iteration A=$A B=$B C=$C"
assert_false hash_isset setup "${CURITER}"

for combo in ${expected_combos}; do
	value=
	assert_true hash_get got "${combo}" value
	assert 1 "${value}" "A=$A B=$B C=$C"
done
