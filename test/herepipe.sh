set -e
. ./common.sh
set +e

{
	TMP="$(mktemp -u)"
	while herepipe_read it line; do
		echo "${line}"
	done > "${TMP}" <<-EOF
	$({
		herepipe_trap
		echo "1 2"
		echo "3 4"
		echo "5"
	})
	EOF
	# Return status is in $it
	assert 0 "${it}"
	assert_file - "${TMP}" <<-EOF
	1 2
	3 4
	5
	EOF
	rm -f "${TMP}"
}

{
	TMP="$(mktemp -u)"
	while herepipe_read it line; do
		echo "${line}"
	done > "${TMP}" <<-EOF
	$({
		herepipe_trap
		echo "1 2"
		echo "3 4"
		echo "5"
		exit 55
	})
	EOF
	# Return status is in $it
	assert 55 "${it}"
	assert_file - "${TMP}" <<-EOF
	1 2
	3 4
	5
	EOF
	rm -f "${TMP}"
}

{
	TMP="$(mktemp -u)"
	while herepipe_read it line; do
		echo "${line}"
	done > "${TMP}" <<-EOF
	$({
		herepipe_trap
	})
	EOF
	# Return status is in $it
	assert 0 "${it}"
	assert_file - "${TMP}" <<-EOF
	EOF
	rm -f "${TMP}"
}

{
	TMP="$(mktemp -u)"
	while herepipe_read it line; do
		echo "${line}"
	done > "${TMP}" <<-EOF
	$({
		herepipe_trap
		exit 25
	})
	EOF
	# Return status is in $it
	assert 25 "${it}"
	assert_file - "${TMP}" <<-EOF
	EOF
	rm -f "${TMP}"
}
