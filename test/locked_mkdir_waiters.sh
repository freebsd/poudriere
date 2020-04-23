set -e
. common.locked_mkdir.sh
set +e

LOCK1="${LOCKBASE}/lock_waiters"

# Multiple waiters - one should win
max=3
n=0
[ -d "${LOCK1}" ]
assert_not 0 $? "$0:$LINENO: Lock dir should not exist"
until [ "${n}" -eq "${max}" ]; do
	[ -d "${LOCK1}" ]
	assert_not 0 $? "$0:$LINENO: Lock dir should not exist"

	echo "$0:$LINENO: Parent pid $$ has lock ${n}"
	time=$(date +%s)
	locked_mkdir 0 ${LOCK1} $$
	assert 0 $? "$0:$LINENO: Lock should succeed"
	assert_pid "$0:$LINENO" "${LOCK1}" "$$"
	nowtime=$(date +%s)
	elapsed=$((${nowtime} - ${time}))
	[ "${elapsed}" -le 3 ]
	assert 0 $? "$0:$LINENO: Lock shouldn't sleep elapsed=${elapsed} ${n}"

	# Background waiters
	(
		mypid=$(sh -c 'echo $PPID')
		time=$(date +%s)
		locked_mkdir 5 "${LOCK1}" "${mypid}"
		got_lock=$?
		echo "$0:$LINENO: Pid ${mypid} got_lock=${got_lock} ${n}"
		nowtime=$(date +%s)
		elapsed=$((${nowtime} - ${time}))
		[ "${elapsed}" -le 7 ]
		assert 0 $? "$0:$LINENO: Lock slept too long elapsed=${elapsed} ${n}"
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
		mypid=$(sh -c 'echo $PPID')
		time=$(date +%s)
		locked_mkdir 5 "${LOCK1}" "${mypid}"
		got_lock=$?
		echo "$0:$LINENO: Pid ${mypid} got_lock=${got_lock} ${n}"
		nowtime=$(date +%s)
		elapsed=$((${nowtime} - ${time}))
		[ "${elapsed}" -le 7 ]
		assert 0 $? "$0:$LINENO: Lock slept too long elapsed=${elapsed} ${n}"
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
		mypid=$(sh -c 'echo $PPID')
		time=$(date +%s)
		locked_mkdir 5 "${LOCK1}" "${mypid}"
		got_lock=$?
		echo "$0:$LINENO: Pid ${mypid} got_lock=${got_lock} ${n}"
		nowtime=$(date +%s)
		elapsed=$((${nowtime} - ${time}))
		[ "${elapsed}" -le 7 ]
		assert 0 $? "$0:$LINENO: Lock slept too long elapsed=${elapsed} ${n}"
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
		mypid=$(sh -c 'echo $PPID')
		time=$(date +%s)
		locked_mkdir 5 "${LOCK1}" "${mypid}"
		got_lock=$?
		echo "$0:$LINENO: Pid ${mypid} got_lock=${got_lock} ${n}"
		nowtime=$(date +%s)
		elapsed=$((${nowtime} - ${time}))
		[ "${elapsed}" -le 7 ]
		assert 0 $? "$0:$LINENO: Lock slept too long elapsed=${elapsed} ${n}"
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

	# Drop the lock for a child to pickup
	sleep 2
	echo "$0:$LINENO: Parent pid $$ dropping lock ${n}"
	rmdir "${LOCK1}"
	assert 0 $? "$0:$LINENO: rmdir should succeed ${n}"

	# XXX: Not sleeping should serialize and all should pass
	# Wait for each to finish its wait task
	sleep 6
	# Now a child should own the lock but only *1* should own it. Failed
	# waiters return 75 (EX_TEMPFAIL). Any other non-zero is fatal.
	_wait "${pid_unlock1}"
	status_unlock1=$?
	_wait "${pid_unlock2}"
	status_unlock2=$?
	_wait "${pid_unlock3}"
	status_unlock3=$?
	_wait "${pid_unlock4}"
	status_unlock4=$?

	nowtime=$(date +%s)

	assert $((75 * 3)) $((status_unlock1 + status_unlock2 + status_unlock3 + \
		status_unlock4)) "$0:$LINENO: 3 waiters should timeout on lock and 1 should win ${n}"
	[ -d "${LOCK1}" ]
	assert 0 $? "$0:$LINENO: Lock dir should exist ${n}"

	# Make sure the one who thinks it won actually did win in the end
	[ "${status_unlock1}" -eq 0 ] && assert_pid "$0:$LINENO" "${LOCK1}" "${pid_unlock1}"
	[ "${status_unlock2}" -eq 0 ] && assert_pid "$0:$LINENO" "${LOCK1}" "${pid_unlock2}"
	[ "${status_unlock3}" -eq 0 ] && assert_pid "$0:$LINENO" "${LOCK1}" "${pid_unlock3}"
	[ "${status_unlock4}" -eq 0 ] && assert_pid "$0:$LINENO" "${LOCK1}" "${pid_unlock4}"

	elapsed=$((${nowtime} - ${time}))
	# This is hard to properly test due to the extra sleeps in the children
	[ "${elapsed}" -le 20 ]
	assert 0 $? "$0:$LINENO: Children locks took too long elapsed=${elapsed} ${n}"

	# Should be able to take the lock immediately now without removing the
	# dir since children are all dead.
	[ -d "${LOCK1}" ]
	assert 0 $? "$0:$LINENO: Lock dir should exist ${n}"
	time=$(date +%s)
	locked_mkdir 2 ${LOCK1} $$
	assert 0 $? "$0:$LINENO: Unlocked dir should succeed to lock ${n}"
	[ -d "${LOCK1}" ]
	assert 0 $? "$0:$LINENO: Lock dir should exist ${n}"
	assert_pid "$0:$LINENO" "${LOCK1}" "$$"
	nowtime=$(date +%s)
	elapsed=$((${nowtime} - ${time}))
	[ "${elapsed}" -lt 4 ]
	assert 0 $? "$0:$LINENO: Unlocked dir should not wait to lock ${n}"

	rmdir "${LOCK1}"
	assert 0 $? "$0:$LINENO: rmdir should succeed ${n}"

	n=$((n + 1))
done

rm -rf "${LOCKBASE}"
