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

	assert_true readlines one < "${TMP}"
	expected="$({
	cat <<-EOF
	1 one
	2 two
	3 thre\e
	4 
	5 five
	  six
	EOF
	})"
	assert "${expected}" "${one}"
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
	EOF

	assert_true readlines one two < "${TMP}"
	assert "1 one" "${one}"
	expected="$({
	cat <<-EOF
	2 two
	3 thre\e
	4 
	5 five
	  six
	EOF
	})"
	assert "${expected}" "${two}"
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

	two=unset
	assert_true readlines one '' three four five six < "${TMP}" > "${TMP}.stdout"
	assert "1 one" "${one}"
	assert "unset" "${two}"
	assert "3 thre\e" "${three}"
	assert "4 " "${four}"
	assert "5 five" "${five}"
	assert "  six"$'\n'"7 seven" "${six}"
	assert 7 "${_readlines_lines_read:?}"
	assert_file - "${TMP}.stdout" <<-EOF
	EOF

	rm -f "${TMP}"
}

{
	unset one three
	assert_false readlines_file /nonexistent one '' three
	assert "null" "${one-null}"
	assert "null" "${three-null}"
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

{
	TMP="$(mktemp -ut readlines.data)"
	TMP2="$(mktemp -ut readlines.stdout)"
	cat > "${TMP}" <<-EOF
	1
	2
	3
	EOF
	assert_true readlines_file "${TMP}" > "${TMP2}"
	assert_file "${TMP}" "${TMP}"
	rm -f "${TMP}" "${TMP2}"
}

{
	TMP="$(mktemp -ut readlines.data)"
	TMP2="$(mktemp -ut readlines.stdout)"
	cat > "${TMP}" <<-EOF
	1
	2
	3
	EOF
	assert_true readlines_file "${TMP}" - > "${TMP2}"
	assert_file "${TMP}" "${TMP}"
	assert 3 "${_readlines_lines_read}"
	rm -f "${TMP}" "${TMP2}"
}

# Teeing
{
	TMP="$(mktemp -ut readlines)"
	cat > "${TMP}" <<-EOF
	1
	2
	EOF
	one=blah
	two=blah
	assert_true readlines_file "${TMP}" one two > "${TMP}.2"
	# No teeing without -T
	assert_ret 1 test -s "${TMP}.2"
	assert_true readlines_file -T "${TMP}" one two > "${TMP}.2"
	assert "1" "${one}"
	assert "2" "${two}"
	assert 2 "${_readlines_lines_read:?}"
	assert_file "${TMP}" "${TMP}.2" "readlines_file -T should tee"
	rm -f "${TMP}" "${TMP}.2"
}

# Teeing
{
	TMP="$(mktemp -ut readlines)"
	cat > "${TMP}" <<-EOF
	1
	2
	EOF
	one=blah
	two=blah
	assert_true readlines one two > "${TMP}.2" <<-EOF
	$(cat "${TMP}")
	EOF
	# No teeing without -T
	assert_ret 1 test -s "${TMP}.2"
	assert_true readlines -T one two > "${TMP}.2" <<-EOF
	$(cat "${TMP}")
	EOF
	assert 0 "$?"
	assert "1" "${one}"
	assert "2" "${two}"
	assert 2 "${_readlines_lines_read:?}"
	assert_file "${TMP}" "${TMP}.2" "readlines -T should tee"
	rm -f "${TMP}" "${TMP}.2"
}
