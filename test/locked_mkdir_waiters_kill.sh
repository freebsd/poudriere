set -e
. common.locked_mkdir.sh
set +e

LOCK1="${LOCKBASE}/lock_waiters"

# Multiple waiters - one should win but killing it should allow another to win
max=1
n=0
[ -d "${LOCK1}" ]
assert_not 0 $? "Lock dir should not exist"
until [ "${n}" -eq "${max}" ]; do
	unset status_unlock1 status_unlock2 status_unlock3 status_unlock4
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
		set -T
		got_lock=66
		trap 'exit ${got_lock}' TERM
		mypid=$(sh -c 'echo $PPID')
		time=$(clock -monotonic)
		locked_mkdir 10 "${LOCK1}" "${mypid}"
		got_lock=$?
		echo "Pid ${mypid} got_lock=${got_lock} ${n}"
		nowtime=$(clock -monotonic)
		elapsed=$((${nowtime} - ${time}))
		[ "${elapsed}" -le 12 ]
		assert 0 $? "Lock slept too long elapsed=${elapsed} ${n}"
		if [ "${got_lock}" -eq 0 ]; then
			assert_pid "$0:$LINENO" "${LOCK1}" "${mypid}" "${n}"
		fi
		if [ "${got_lock}" -eq 0 ]; then
			# Wait a bit to not allow other waiters to win
			sleep 10
		fi
		exit ${got_lock}
	) &
	pid_unlock1=$!
	(
		trap - INT
		set -T
		got_lock=66
		trap 'exit ${got_lock}' TERM
		mypid=$(sh -c 'echo $PPID')
		time=$(clock -monotonic)
		locked_mkdir 10 "${LOCK1}" "${mypid}"
		got_lock=$?
		echo "Pid ${mypid} got_lock=${got_lock} ${n}"
		nowtime=$(clock -monotonic)
		elapsed=$((${nowtime} - ${time}))
		[ "${elapsed}" -le 12 ]
		assert 0 $? "Lock slept too long elapsed=${elapsed} ${n}"
		if [ "${got_lock}" -eq 0 ]; then
			assert_pid "$0:$LINENO" "${LOCK1}" "${mypid}" "${n}"
		fi
		if [ "${got_lock}" -eq 0 ]; then
			# Wait a bit to not allow other waiters to win
			sleep 10
		fi
		exit ${got_lock}
	) &
	pid_unlock2=$!
	(
		trap - INT
		set -T
		got_lock=66
		trap 'exit ${got_lock}' TERM
		mypid=$(sh -c 'echo $PPID')
		time=$(clock -monotonic)
		locked_mkdir 10 "${LOCK1}" "${mypid}"
		got_lock=$?
		echo "Pid ${mypid} got_lock=${got_lock} ${n}"
		nowtime=$(clock -monotonic)
		elapsed=$((${nowtime} - ${time}))
		[ "${elapsed}" -le 12 ]
		assert 0 $? "Lock slept too long elapsed=${elapsed} ${n}"
		if [ "${got_lock}" -eq 0 ]; then
			assert_pid "$0:$LINENO" "${LOCK1}" "${mypid}" "${n}"
		fi
		if [ "${got_lock}" -eq 0 ]; then
			# Wait a bit to not allow other waiters to win
			sleep 10
		fi
		exit ${got_lock}
	) &
	pid_unlock3=$!
	(
		trap - INT
		set -T
		got_lock=66
		trap 'exit ${got_lock}' TERM
		mypid=$(sh -c 'echo $PPID')
		time=$(clock -monotonic)
		locked_mkdir 10 "${LOCK1}" "${mypid}"
		got_lock=$?
		echo "Pid ${mypid} got_lock=${got_lock} ${n}"
		nowtime=$(clock -monotonic)
		elapsed=$((${nowtime} - ${time}))
		[ "${elapsed}" -le 12 ]
		assert 0 $? "Lock slept too long elapsed=${elapsed} ${n}"
		if [ "${got_lock}" -eq 0 ]; then
			assert_pid "$0:$LINENO" "${LOCK1}" "${mypid}" "${n}"
		fi
		if [ "${got_lock}" -eq 0 ]; then
			# Wait a bit to not allow other waiters to win
			sleep 10
		fi
		exit ${got_lock}
	) &
	pid_unlock4=$!

	# Drop the lock for a child to pickup
	sleep 2
	echo "Parent pid $$ dropping lock ${n}"
	rmdir "${LOCK1}"
	assert 0 $? "rmdir should succeed ${n}"

	# Wait a sec and find out who won
	sleep 2
	# cat for missing newline
	winner=$(cat "${LOCK1}.pid")
	[ -d "${LOCK1}" ]
	assert 0 $? "Lock dir should exist ${n}"
	# Sanity check
	sleep 1
	[ -d "${LOCK1}" ]
	assert 0 $? "Lock dir should exist ${n}"
	assert_pid "$0:$LINENO" "${LOCK1}" "${winner}" "Winner shouldn't change ${n}"
	# Kill winner and let another win
	kill "${winner}"
	_wait "${winner}"
	case ${winner} in
	"${pid_unlock1}") status_unlock1=$? ;;
	"${pid_unlock2}") status_unlock2=$? ;;
	"${pid_unlock3}") status_unlock3=$? ;;
	"${pid_unlock4}") status_unlock4=$? ;;
	esac
	# New winner
	sleep 2
	# cat for missing newline
	winner2=$(cat "${LOCK1}.pid")
	[ -d "${LOCK1}" ]
	assert 0 $? "Lock dir should exist ${n}"
	assert_not ${winner} ${winner2} "New winner should not match as it was killed ${n}"
	# Sanity check
	sleep 1
	[ -d "${LOCK1}" ]
	assert 0 $? "Lock dir should exist ${n}"
	assert_pid "$0:$LINENO" "${LOCK1}" "${winner2}" "Winner shouldn't change ${n}"
	# All good, cleanup children

	# Now a child should own the lock but only *1* should own it (one will
	# exit success though since it had it). Failed
	# waiters return 124 on timeout. Any other non-zero is fatal.
	if [ -z "${status_unlock1}" ]; then
		_wait "${pid_unlock1}"
		status_unlock1=$?
	fi
	if [ -z "${status_unlock2}" ]; then
		_wait "${pid_unlock2}"
		status_unlock2=$?
	fi
	if [ -z "${status_unlock3}" ]; then
		_wait "${pid_unlock3}"
		status_unlock3=$?
	fi
	if [ -z "${status_unlock4}" ]; then
		_wait "${pid_unlock4}"
		status_unlock4=$?
	fi

	nowtime=$(clock -monotonic)

	assert $((124 * 2)) $((status_unlock1 + status_unlock2 + status_unlock3 + \
		status_unlock4)) "2 waiters should timeout on lock, 1 should win, 1 should be OK after TERMed after winning ${n}"
	[ -d "${LOCK1}" ]
	assert 0 $? "Lock dir should exist ${n}"

	# Make sure the one who thinks it won actually did win in the end
	[ -d "${LOCK1}" ]
	assert 0 $? "Lock dir should exist ${n}"
	assert_pid "$0:$LINENO" "${LOCK1}" "${winner2}" "Winner shouldn't change ${n}"

	elapsed=$((${nowtime} - ${time}))
	# This is hard to properly test due to the extra sleeps in the children
	[ "${elapsed}" -le 30 ]
	assert 0 $? "Children locks took too long elapsed=${elapsed} ${n}"

	# Should be able to take the lock immediately now without removing the
	# dir since children are all dead.
	[ -d "${LOCK1}" ]
	assert 0 $? "Lock dir should exist ${n}"
	time=$(clock -monotonic)
	locked_mkdir 2 ${LOCK1} $$
	assert 0 $? "Unlocked dir should succeed to lock ${n}"
	[ -d "${LOCK1}" ]
	assert 0 $? "Lock dir should exist ${n}"
	assert_pid "$0:$LINENO" "${LOCK1}" "$$"
	nowtime=$(clock -monotonic)
	elapsed=$((${nowtime} - ${time}))
	[ "${elapsed}" -lt 4 ]
	assert 0 $? "Unlocked dir should not wait to lock ${n}"

	rmdir "${LOCK1}"
	assert 0 $? "rmdir should succeed ${n}"

	n=$((n + 1))
done

rm -rf "${LOCKBASE}"
