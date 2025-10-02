set -e
. ./common.sh
set +e

MASTERMNT=$(mktemp -d)

writer() {
	while :; do
		{
			shash_write bucket key || exit 2
		} <<-EOF
		value
		EOF
	done
}

echo "Working on ${MASTERMNT}"
SHASH_VAR_PATH="${MASTERMNT}"

{
	spawn_job writer
	writerjob="${spawn_jobid}"
	writerpid="$!"
	assert_true kill -0 "${writerpid}"
	assert_true kill "%${writerjob}"
	assert_ret 143 timed_wait_and_kill_job 10 "%${writerjob}"
}

{
	spawn_job writer
	writerjob="${spawn_jobid}"
	writerpid="$!"
	assert_true kill -0 "${writerpid}"
	attempts=1000
	# attempts=1
	n=0
	sleep 1
	until [ "${n}" -eq "${attempts}" ]; do
		unset var
		if var="$(shash_read bucket key)"; then
			# If shash_get succeeds we must have a value.
			assert "value" "${var-__null}" "n=${n}"
		fi
		n="$((n + 1))"
	done
	assert_true kill "%${writerjob}"
	assert_ret 143 timed_wait_and_kill_job 10 "%${writerjob}"
}

rm -rf "${MASTERMNT}"
exit 0
