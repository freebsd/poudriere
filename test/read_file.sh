set -e
. common.sh
set +e

set_test_contexts - '' '' <<-EOF
READ_FILE_USE_CAT 0 1
EOF

while get_test_context; do
	TMP=$(mktemp -u)
	data=blah
	read_file data "${TMP}"
	assert_not 0 $? "read_file on missing file should not return 0"
	assert '' "${data}" "read_file on missing file should be blank"
	assert 'NULL' "${data-NULL}" "read_file on missing file should unset vars"
	assert 0 "${_read_file_lines_read}" "_read_file_lines_read should be 0 on missing file"

	echo "first" >> "${TMP}"
	read_file data "${TMP}"
	assert 'first' "${data}" "read_file on 1 line file should match"
	assert 1 "${_read_file_lines_read}" "_read_file_lines_read"

	data=blah
	echo "second" >> "${TMP}"
	read_file data "${TMP}"
	assert $'first\nsecond' "${data}" "read_file on 2 line file should match"
	assert 2 "${_read_file_lines_read}" "_read_file_lines_read"

	data=blah
	echo "third" >> "${TMP}"
	read_file data "${TMP}"
	assert $'first\nsecond\nthird' "${data}" "read_file on 3 line file should match"
	assert 3 "${_read_file_lines_read}" "_read_file_lines_read"

	data=blah
	echo "fourth" >> "${TMP}"
	read_file '' "${TMP}"
	assert "blah" "${data}" "read_file shouldn't have touched var"
	assert 4 "${_read_file_lines_read}" "_read_file_lines_read"

	rm -f "${TMP}"
done
