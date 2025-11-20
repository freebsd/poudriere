set -e
. common.locked_mkdir.sh
set +e
LOCK1="${LOCKBASE}/lock1"

# Take first lock
time=$(clock -monotonic)
locked_mkdir 10 ${LOCK1} $$
assert 0 $? "Unlocked dir should succeed to lock"
[ -d "${LOCK1}" ]
assert 0 $? "Lock dir should exist"
assert_pid "$0:$LINENO" "${LOCK1}" "$$"
nowtime=$(clock -monotonic)
elapsed=$((${nowtime} - ${time}))
[ "${elapsed}" -lt 5 ]
assert 0 $? "Unlocked dir should not wait to lock"

# Wait on and fail to take owned lock
time=$(clock -monotonic)
locked_mkdir 2 ${LOCK1} $$
assert 124 $? "Locked dir should timeout"
nowtime=$(clock -monotonic)
elapsed=$((${nowtime} - ${time}))
[ "${elapsed}" -le 3 ]
assert 0 $? "Lock sleep took too long. elapsed=${elapsed}"
[ -d "${LOCK1}" ]
assert 0 $? "Lock dir should exist"

# Drop lock and retake it
rmdir "${LOCK1}"
assert 0 $? "rmdir should succeed"
time=$(clock -monotonic)
locked_mkdir 10 ${LOCK1} $$
assert 0 $? "Unlocked dir should succeed to lock"
assert_pid "$0:$LINENO" "${LOCK1}" "$$"
nowtime=$(clock -monotonic)
elapsed=$((${nowtime} - ${time}))
[ "${elapsed}" -lt 5 ]
assert 0 $? "Unlocked dir should not wait to lock"
[ -d "${LOCK1}" ]
assert 0 $? "Lock dir should exist"

# Wait on and succeed taking owned lock
time=$(clock -monotonic)
# Background process to drop the lock
(
	trap - INT
	sleep 5
	rmdir "${LOCK1}"
	assert 0 $? "rmdir should succeed"
) &
pid_unlock=$!
locked_mkdir 10 ${LOCK1} $$
assert 0 $? "Lock should succeed"
assert_pid "$0:$LINENO" "${LOCK1}" "$$"
nowtime=$(clock -monotonic)
elapsed=$((${nowtime} - ${time}))
[ "${elapsed}" -le 6 ]
assert 0 $? "Lock slept too long elapsed=${elapsed}"
[ -d "${LOCK1}" ]
assert 0 $? "Lock dir should exist"
wait
assert 0 $? "children should exit cleanly"

# Stale pid without dir
rmdir "${LOCK1}"
assert 0 $? "rmdir should succeed"
echo 999999 > "${LOCK1}.pid"
assert 0 $? "Writing to pid should succeed"
time=$(clock -monotonic)
locked_mkdir 10 ${LOCK1} $$
assert 0 $? "Unlocked existing dir with stale pid should succeed to lock"
assert_pid "$0:$LINENO" "${LOCK1}" "$$"
nowtime=$(clock -monotonic)
elapsed=$((${nowtime} - ${time}))
[ "${elapsed}" -lt 3 ]
assert 0 $? "Unlocked dir should not wait to lock"
[ -d "${LOCK1}" ]
assert 0 $? "Lock dir should exist"

# Stale pid with dir
[ -d "${LOCK1}" ]
assert 0 $? "Lock dir should exist"
echo 999999 > "${LOCK1}.pid"
assert 0 $? "Writing to pid should succeed"
time=$(clock -monotonic)
locked_mkdir 10 ${LOCK1} $$
assert 0 $? "Unlocked existing dir with stale pid should succeed to lock"
assert_pid "$0:$LINENO" "${LOCK1}" "$$"
nowtime=$(clock -monotonic)
elapsed=$((${nowtime} - ${time}))
[ "${elapsed}" -lt 3 ]
assert 0 $? "Unlocked dir should not wait to lock"
[ -d "${LOCK1}" ]
assert 0 $? "Lock dir should exist"

# Sanity check taking lock owned by not our pid
[ -d "${LOCK1}" ]
assert 0 $? "Lock dir should exist"
time=$(clock -monotonic)
echo 1 > "${LOCK1}.pid"
assert 0 $? "Writing to pid should succeed"
assert_pid "$0:$LINENO" "${LOCK1}" "1"
locked_mkdir 5 ${LOCK1} $$
assert 124 $? "Lock should not succeed"
assert_pid "$0:$LINENO" "${LOCK1}" "1"
nowtime=$(clock -monotonic)
elapsed=$((${nowtime} - ${time}))
[ "${elapsed}" -le 6 ]
assert 0 $? "Lock slept too long elapsed=${elapsed}"
[ -d "${LOCK1}" ]
assert 0 $? "Lock dir should exist"

# Try taking lock with running pid but no dir which is considered stale
rmdir "${LOCK1}"
assert 0 $? "rmdir should succeed"
time=$(clock -monotonic)
echo 1 > "${LOCK1}.pid"
assert 0 $? "Writing to pid should succeed"
assert_pid "$0:$LINENO" "${LOCK1}" "1"
locked_mkdir 5 ${LOCK1} $$
assert 0 $? "Lock should succeed"
assert_pid "$0:$LINENO" "${LOCK1}" "$$"
nowtime=$(clock -monotonic)
elapsed=$((${nowtime} - ${time}))
[ "${elapsed}" -le 2 ]
assert 0 $? "Lock waiting too long elapsed=${elapsed}"

rm -rf "${LOCKBASE}"
