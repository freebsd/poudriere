set -e
. ./common.sh
set +e

set_pipefail

{
	TMP=localfile
	assert_false [ -e "${TMP}" ]
	assert_true write_atomic "${TMP}" "1"
	assert_file - "${TMP}" <<-EOF
	1
	EOF
	rm -f "${TMP}"
}

{
	TMP=$(mktemp -t mapfile)
	TMP2=$(mktemp -t mapfile)
	TMP3=$(mktemp -ut mapfile)

	ps uaxwd > "${TMP}"

	# This pattern is testing that the file is not written until close.
	# And that teeing does not happen.
	write_atomic "${TMP2}" "$(cat "${TMP}"; rm -rf "${TMP2}")" > "${TMP3}"
	assert 0 "$?" "pipe exit status"
	assert_ret 0 diff -u "${TMP}" "${TMP2}"
	assert_ret 1 [ -s "${TMP3}" ]
	rm -f "${TMP3}"

	# Test that a new write happens with a new inode
	tmp2_ino=$(stat -f %i "${TMP2}")
	assert_ret 0 write_atomic "${TMP2}" "$(cat "${TMP}")"
	assert_ret 0 diff -u "${TMP}" "${TMP2}"
	assert_not "${tmp2_ino}" "$(stat -f %i "${TMP2}")"

	rm -f "${TMP}" "${TMP2}"
}

# Test noclobber
{
	TMP=$(mktemp -t mapfile)
	TMP2=$(mktemp -t mapfile)

	ps uaxwd > "${TMP}"

	echo "noclobber" > "${TMP2}"

	# With noclobber we should get no modification to TMP2.
	noclobber write_atomic "${TMP2}" "$(cat "${TMP}")"
	assert 1 "$?" "pipe exit status"
	assert_file - "${TMP2}" <<-EOF
	noclobber
	EOF
	rm -f "${TMP}"
}

# Test teeing.
{
	TMP=$(mktemp -t mapfile)
	TMP2=$(mktemp -t mapfile)
	TMP3=$(mktemp -t mapfile)

	ps uaxwd > "${TMP}"

	# This pattern is testing that the file is not written until close.
	# And that teeing does happen.
	write_atomic -T "${TMP2}" "$(cat "${TMP}"; rm -rf "${TMP2}")" > "${TMP3}"
	assert 0 "$?" "pipe exit status"
	assert_ret 0 diff -u "${TMP}" "${TMP2}"
	assert_ret 0 diff -u "${TMP}" "${TMP3}"
	rm -f "${TMP}" "${TMP2}" "${TMP3}"
}

# Test multi-param data
{
	TMP="$(mktemp -t mapfile)"
	TMP3="$(mktemp -t mapfile)"
	write_atomic -T "${TMP}" "1" "2" > "${TMP3}"
	assert 0 "$?"
	assert_file - "${TMP}" <<-EOF
	1 2
	EOF
	assert_file - "${TMP3}" <<-EOF
	1 2
	EOF
	rm -f "${TMP3}"
}

# Test multi-param data
{
	TMP="$(mktemp -t mapfile)"
	TMP3="$(mktemp -t mapfile)"
	write_atomic -T "${TMP}" "1" "2" > "${TMP3}"
	assert 0 "$?"
	assert_file - "${TMP}" <<-EOF
	1 2
	EOF
	assert_file - "${TMP3}" <<-EOF
	1 2
	EOF
	rm -f "${TMP3}"
}
