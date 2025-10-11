set -e
. common.locked_mkdir.sh
set +e

LOCK1="${LOCKBASE}/lock_waiters"

# Multiple waiters - none should win
max=1
n=0
[ -d "${LOCK1}" ]
assert_not 0 $? "Lock dir should not exist"
until [ "${n}" -eq "${max}" ]; do
	[ -d "${LOCK1}" ]
	assert_not 0 $? "Lock dir should not exist"

	echo "Parent pid $$ has lock ${n}"
	time=$(clock -monotonic)
	locked_mkdir 0 ${LOCK1} $$
	assert 0 $? "Lock should succeed"
	assert_pid "$0:$LINENO" "${LOCK1}" "$$"
	nowtime=$(clock -monotonic)
	elapsed=$((${nowtime} - ${time}))
	[ "${elapsed}" -le 3 ]
	assert 0 $? "Lock shouldn't sleep elapsed=${elapsed} ${n}"

	# Background waiters
	(
		trap - INT
		mypid=$(sh -c 'echo $PPID')
		time=$(clock -monotonic)
		locked_mkdir 5 "${LOCK1}" "${mypid}"
		got_lock=$?
		echo "Pid ${mypid} got_lock=${got_lock} ${n}"
		nowtime=$(clock -monotonic)
		elapsed=$((${nowtime} - ${time}))
		[ "${elapsed}" -le 7 ]
		assert 0 $? "Lock slept too long elapsed=${elapsed} ${n}"
		if [ "${got_lock}" -eq 0 ]; then
			assert_pid "$0:$LINENO" "${LOCK1}" "${mypid}" "${n}"
		fi
		if [ "${got_lock}" -eq 0 ]; then
			# Wait a bit to not allow other waiters to win
			sleep 7
		fi
		exit ${got_lock}
	) &
	pid_unlock1=$!
	(
		trap - INT
		mypid=$(sh -c 'echo $PPID')
		time=$(clock -monotonic)
		locked_mkdir 5 "${LOCK1}" "${mypid}"
		got_lock=$?
		echo "Pid ${mypid} got_lock=${got_lock} ${n}"
		nowtime=$(clock -monotonic)
		elapsed=$((${nowtime} - ${time}))
		[ "${elapsed}" -le 7 ]
		assert 0 $? "Lock slept too long elapsed=${elapsed} ${n}"
		if [ "${got_lock}" -eq 0 ]; then
			assert_pid "$0:$LINENO" "${LOCK1}" "${mypid}" "${n}"
		fi
		if [ "${got_lock}" -eq 0 ]; then
			# Wait a bit to not allow other waiters to win
			sleep 7
		fi
		exit ${got_lock}
	) &
	pid_unlock2=$!
	(
		trap - INT
		mypid=$(sh -c 'echo $PPID')
		time=$(clock -monotonic)
		locked_mkdir 5 "${LOCK1}" "${mypid}"
		got_lock=$?
		echo "Pid ${mypid} got_lock=${got_lock} ${n}"
		nowtime=$(clock -monotonic)
		elapsed=$((${nowtime} - ${time}))
		[ "${elapsed}" -le 7 ]
		assert 0 $? "Lock slept too long elapsed=${elapsed} ${n}"
		if [ "${got_lock}" -eq 0 ]; then
			assert_pid "$0:$LINENO" "${LOCK1}" "${mypid}" "${n}"
		fi
		if [ "${got_lock}" -eq 0 ]; then
			# Wait a bit to not allow other waiters to win
			sleep 7
		fi
		exit ${got_lock}
	) &
	pid_unlock3=$!
	(
		trap - INT
		mypid=$(sh -c 'echo $PPID')
		time=$(clock -monotonic)
		locked_mkdir 5 "${LOCK1}" "${mypid}"
		got_lock=$?
		echo "Pid ${mypid} got_lock=${got_lock} ${n}"
		nowtime=$(clock -monotonic)
		elapsed=$((${nowtime} - ${time}))
		[ "${elapsed}" -le 7 ]
		assert 0 $? "Lock slept too long elapsed=${elapsed} ${n}"
		if [ "${got_lock}" -eq 0 ]; then
			assert_pid "$0:$LINENO" "${LOCK1}" "${mypid}" "${n}"
		fi
		if [ "${got_lock}" -eq 0 ]; then
			# Wait a bit to not allow other waiters to win
			sleep 7
		fi
		exit ${got_lock}
	) &
	pid_unlock4=$!

	# All should fail
	_wait "${pid_unlock1}"
	status_unlock1=$?
	_wait "${pid_unlock2}"
	status_unlock2=$?
	_wait "${pid_unlock3}"
	status_unlock3=$?
	_wait "${pid_unlock4}"
	status_unlock4=$?

	nowtime=$(clock -monotonic)

	assert $((124 * 4)) $((status_unlock1 + status_unlock2 + status_unlock3 + \
		status_unlock4)) "4 waiters should timeout on lock ${n}"
	[ -d "${LOCK1}" ]
	assert 0 $? "Lock dir should exist ${n}"
	assert_pid "$0:$LINENO" "${LOCK1}" "$$" "I should own the lock still ${n}"

	elapsed=$((${nowtime} - ${time}))
	# This is hard to properly test due to the extra sleeps in the children
	[ "${elapsed}" -ge 4 -a "${elapsed}" -le 10 ]
	assert 0 $? "Children lock timeouts were out of range elapsed=${elapsed} ${n}"

	rmdir "${LOCK1}"
	assert 0 $? "rmdir should succeed ${n}"

	n=$((n + 1))
done

rm -rf "${LOCKBASE}"
