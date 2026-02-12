set -e
. ./common.sh
set +e

set_pipefail

{
	TMP=$(mktemp -t mapfile)
	TMP2=$(mktemp -t mapfile)
	TMP3=$(mktemp -ut mapfile)

	generate_data > "${TMP}"

	# This pattern is testing that the file is not written until close.
	# And that teeing does not happen.
	( cat "${TMP}"; rm -f "${TMP2}"; ) | write_atomic_cmp "${TMP2}" > "${TMP3}"
	assert 0 "$?" "pipe exit status"
	assert_ret 0 diff -u "${TMP}" "${TMP2}"
	assert_ret 1 [ -s "${TMP3}" ]
	rm -f "${TMP3}"

	# Because the output matches we should get a successful write but
	# the same inode.
	tmp2_ino=$(stat -f %i "${TMP2}")
	assert_ret 0 write_atomic_cmp "${TMP2}" <<-EOF
	$(cat "${TMP}")
	EOF
	assert_ret 0 diff -u "${TMP}" "${TMP2}"
	assert "${tmp2_ino}" "$(stat -f %i "${TMP2}")"

	rm -f "${TMP}" "${TMP2}"
}

# Test noclobber
# write_atomic_cmp+noclobber is basically just write_atomic_if_no_file.
{
	TMP=$(mktemp -t mapfile)
	TMP2=$(mktemp -t mapfile)

	generate_data > "${TMP}"

	echo "noclobber" > "${TMP2}"

	# With noclobber we should get no modification to TMP2.
	( cat "${TMP}"; ) | noclobber write_atomic_cmp "${TMP2}"
	assert 1 "$?" "pipe exit status"
	assert_file - "${TMP2}" <<-EOF
	noclobber
	EOF

	cp -f "${TMP}" "${TMP2}"
	tmp2_ino=$(stat -f %i "${TMP2}")
	# With noclobber we should get no modification to TMP2.
	( cat "${TMP}"; ) | noclobber write_atomic_cmp "${TMP2}"
	assert 1 "$?" "pipe exit status"
	assert_ret 0 diff -u "${TMP}" "${TMP2}"
	assert "${tmp2_ino}" "$(stat -f %i "${TMP2}")"
	rm -f "${TMP}" "${TMP2}"
}

# Test teeing.
{
	TMP=$(mktemp -t mapfile)
	TMP2=$(mktemp -t mapfile)
	TMP3=$(mktemp -t mapfile)

	generate_data > "${TMP}"

	# This pattern is testing that the file is not written until close.
	# And that teeing does happen.
	( cat "${TMP}"; rm -f "${TMP2}"; ) | write_atomic_cmp -T "${TMP2}" > "${TMP3}"
	assert 0 "$?" "pipe exit status"
	assert_ret 0 diff -u "${TMP}" "${TMP2}"
	assert_ret 0 diff -u "${TMP}" "${TMP3}"
	rm -f "${TMP}" "${TMP2}" "${TMP3}"
}
