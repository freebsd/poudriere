set -e
. common.sh
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

	assert_true readlines one two three four five six < "${TMP}"
	assert "1 one" "${one}"
	assert "2 two" "${two}"
	assert "3 thre\e" "${three}"
	assert "4 " "${four}"
	assert "5 five" "${five}"
	assert "  six" "${six}"
	assert 6 "${_readlines_lines_read:?}"

	rm -f "${TMP}"
}

{
	TMP="$(mktemp -ut readlines)"
	cat > "${TMP}" <<-EOF
	1 one
	2 two
	3 thre\e
	4 
	5 five
	  six
	7 seven
	EOF

	assert_true readlines one two three four five six < "${TMP}"
	assert "1 one" "${one}"
	assert "2 two" "${two}"
	assert "3 thre\e" "${three}"
	assert "4 " "${four}"
	assert "5 five" "${five}"
	assert "  six"$'\n'"7 seven" "${six}"
	assert 7 "${_readlines_lines_read:?}"

	rm -f "${TMP}"
}

{
	TMP="$(mktemp -ut readlines)"
	: > "${TMP}"
	one=blah
	two=blah
	assert_true readlines_file "${TMP}" one two
	assert "" "${one}"
	assert "NULL" "${one-NULL}"
	assert "" "${two}"
	assert "NULL" "${two-NULL}"
	assert 0 "${_readlines_lines_read:?}"
	rm -f "${TMP}"
}

{
	one=blah
	two=blah
	assert_false readlines_file /nonexistent one two
	assert "" "${one}"
	assert "NULL" "${one-NULL}"
	assert "" "${two}"
	assert "NULL" "${two-NULL}"
	assert 0 "${_readlines_lines_read:?}"
}
