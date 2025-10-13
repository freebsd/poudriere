SLEEPTIME=5

set -e
. ./common.sh
set +e

# Acquire TEST
{
	time=$(clock -monotonic)
	lock_acquire TEST ${SLEEPTIME}
	assert 0 $? "lock_acquire failed"
	nowtime=$(clock -monotonic)
	elapsed=$((${nowtime} - ${time}))
	if [ ${elapsed} -ge ${SLEEPTIME} ]; then
		result=slept
	else
		result=nowait
	fi
	assert nowait ${result} "lock_acquire(TEST) should not have slept, elapsed: ${elapsed}"

	lock_have TEST
	assert 0 $? "lock_have(TEST) should be true"
}

# Acquire second lock TEST2
{
	lock_have TEST2
	assert 1 $? "lock_have(TEST2) should be false"

	time=$(clock -monotonic)
	lock_acquire TEST2 ${SLEEPTIME}
	assert 0 $? "lock_acquire failed"
	nowtime=$(clock -monotonic)
	elapsed=$((${nowtime} - ${time}))
	if [ ${elapsed} -ge ${SLEEPTIME} ]; then
		result=slept
	else
		result=nowait
	fi
	assert nowait ${result} "lock_acquire(TEST2) should not have slept, elapsed: ${elapsed}"
}

# Ensure TEST is held
# XXX: Recursion is allowed now
false &&
{
	time=$(clock -monotonic)
	lock_acquire TEST ${SLEEPTIME}
	assert 1 $? "lock TEST acquired but should be held"
	nowtime=$(clock -monotonic)
	elapsed=$((${nowtime} - ${time}))
	if [ ${elapsed} -ge ${SLEEPTIME} ]; then
		result=slept
	else
		result=nowait
	fi
	assert slept ${result} "lock_acquire(TEST) should have slept, elapsed: ${elapsed}"

	lock_have TEST
	assert 0 $? "lock_have(TEST) should be true"
}

# Release TEST, but releasing return status is unreliable.
{
	lock_have TEST
	assert 0 $? "lock_have(TEST) should be true"
	lock_release TEST
	assert 0 $? "lock_release(TEST) did not succeed"
	lock_have TEST
	assert 1 $? "lock_have(TEST) should be false"
	lock_have TEST2
	assert 0 $? "lock_have(TEST2) should be true"
}

# Reacquire TEST to ensure it was released
{
	time=$(clock -monotonic)
	lock_acquire TEST ${SLEEPTIME}
	assert 0 $? "lock_acquire failed"
	nowtime=$(clock -monotonic)
	elapsed=$((${nowtime} - ${time}))
	if [ ${elapsed} -ge ${SLEEPTIME} ]; then
		result=slept
	else
		result=nowait
	fi
	assert nowait ${result} "lock_acquire(TEST) should not have slept, elapsed: ${elapsed}"
}

{
	lock_release TEST2
	assert 0 $? "lock_release(TEST2) did not succeed"
}

# Reacquire TEST2 to ensure it was released
{
	time=$(clock -monotonic)
	lock_acquire TEST2 ${SLEEPTIME}
	assert 0 $? "lock_acquire failed"
	nowtime=$(clock -monotonic)
	elapsed=$((${nowtime} - ${time}))
	if [ ${elapsed} -ge ${SLEEPTIME} ]; then
		result=slept
	else
		result=nowait
	fi
	assert nowait ${result} "lock_acquire(TEST2) should not have slept, elapsed: ${elapsed}"
}

{
	lock_release TEST
	assert 0 $? "lock_release(TEST) did not succeed"
}

{
	lock_release TEST2
	assert 0 $? "lock_release(TEST2) did not succeed"
}

# Recursive test
{
	lock_acquire TEST ${SLEEPTIME}
	assert 0 $? "lock_acquire(TEST) did not succeed"
	lock_acquire TEST ${SLEEPTIME}
	assert 0 $? "lock_acquire(TEST) did not succeed recursively"
	lock_release TEST
	assert 0 $? "lock_release(TEST) did not succeed recursively"
	lock_release TEST
	assert 0 $? "lock_release(TEST) did not succeed"
}

# Should not be able to acquire or release a child's lock
{
	lock_have TEST
	assert 1 $? "Should not have lock"
	SYNC_FIFO="$(mktemp -ut poudriere.lock)"
	mkfifo "${SYNC_FIFO}"
	(
		trap - INT

		lock_acquire TEST 5
		assert 0 "$?" "Should get lock"
		lock_have TEST
		assert 0 $? "Should have lock"
		write_pipe "${SYNC_FIFO}" "have_lock"
		assert 0 "$?" "write_pipe"
		read_pipe "${SYNC_FIFO}" waiting
		lock_release TEST
		assert 0 "$?" "lock_release"
	) &
	lockpid=$!

	read_pipe "${SYNC_FIFO}" line
	assert 0 "$?" "read_pipe"
	assert "have_lock" "${line}"
	lock_have TEST
	assert 1 $? "Should not have lock"

	# Try to acquire the child's lock - should not work
	lock_acquire TEST 1
	assert_not 0 "$?" "lock_acquire on child's lock should fail"
	(lock_acquire TEST 1)
	assert_not 0 "$?" "lock_acquire on child's lock should fail"
	# Try to drop the lock - should not work
	catch_err lock_release TEST
	assert_not 0 "$?" "Can't release lock not owned"
	(lock_release TEST)
	assert_not 0 "$?" "Can't release lock not owned"

	write_pipe "${SYNC_FIFO}" done
	rm -f "${SYNC_FIFO}"
	_wait "${lockpid}"
	assert 0 "$?" "Child should pass asserts"
}

# Should not be able to acquire or release a parent's lock
{
	lock_have TEST
	assert 1 $? "Should not have lock"
	lock_acquire TEST 5
	assert 0 "$?" "Should get lock"

	(
		trap - INT

		lock_have TEST
		assert 1 $? "Should not have lock in child from parent"
		lock_acquire TEST 5
		assert_not 0 "$?" "Should not get lock"
		lock_have TEST
		assert 1 $? "Should not have lock in child from parent"
		catch_err lock_release TEST
		assert_not 0 "$?" "Should not be able to release parent lock"
		lock_have TEST
		assert 1 $? "Should not have lock in child from parent"
	) &
	lockpid=$!

	_wait "${lockpid}"
	assert 0 "$?" "Child should pass asserts"
	lock_have TEST
	assert 0 $? "Should have lock"
	lock_release TEST
	assert 0 "$?" "lock_release"
}
