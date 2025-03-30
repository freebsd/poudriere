set -e
. ./common.sh
set +e

{
	TMP="$(mktemp -ut readlines)"
	cat > "${TMP}" <<-EOF
	1 one
	2 two
	3 thre\e
	4 
	5 five
	  six
	EOF

	assert_true readarray ARRAY < "${TMP}"
	assert 6 "$(array_size ARRAY)"
	assert "1 one" "$(array_get ARRAY 0)"
	assert "2 two" "$(array_get ARRAY 1)"
	assert "3 thre\e" "$(array_get ARRAY 2)"
	assert "4 " "$(array_get ARRAY 3)"
	assert "5 five" "$(array_get ARRAY 4)"
	assert "  six" "$(array_get ARRAY 5)"

	rm -f "${TMP}"
}

{
	assert_true array_unset ARRAY
	assert_false array_isset ARRAY
	TMP="$(mktemp -ut readlines)"
	cat > "${TMP}" <<-EOF
	1 one
	2 two
	3 thre\e
	4 
	5 five
	  six
	EOF

	assert_true readarray_file "${TMP}" ARRAY
	assert 6 "$(array_size ARRAY)"
	assert "1 one" "$(array_get ARRAY 0)"
	assert "2 two" "$(array_get ARRAY 1)"
	assert "3 thre\e" "$(array_get ARRAY 2)"
	assert "4 " "$(array_get ARRAY 3)"
	assert "5 five" "$(array_get ARRAY 4)"
	assert "  six" "$(array_get ARRAY 5)"

	rm -f "${TMP}"
}
