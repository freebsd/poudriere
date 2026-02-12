set -e
. ./common.sh
set +e

MASTERMNT=$(mktemp -d)

writer() {
	local tmp

	unset tmp
	while time_bounded_loop tmp 90; do
		shash_set bucket key value || exit 2
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
	attempts=100
	# attempts=1
	n=0
	sleep 1
	until [ "${n}" -eq "${attempts}" ]; do
		unset var
		if shash_get bucket key var; then
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
