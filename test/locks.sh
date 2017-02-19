#! /bin/sh

SLEEPTIME=5

. common.sh
. ${SCRIPTPREFIX}/common.sh
LOCK=$(mktemp -ut poudriere-locks)

# Acquire TEST
{
	time=$(date +%s)
	lock_acquire TEST ${SLEEPTIME}
	assert 0 $? "lock_acquire failed"
	nowtime=$(date +%s)
	elapsed=$((${nowtime} - ${time}))
	if [ ${elapsed} -ge ${SLEEPTIME} ]; then
		result=slept
	else
		result=nowait
	fi
	assert nowait ${result} "lock_acquire(TEST) should not have slept, elapsed: ${elapsed}"
}

# Acquire second lock TEST2
{
	time=$(date +%s)
	lock_acquire TEST2 ${SLEEPTIME}
	assert 0 $? "lock_acquire failed"
	nowtime=$(date +%s)
	elapsed=$((${nowtime} - ${time}))
	if [ ${elapsed} -ge ${SLEEPTIME} ]; then
		result=slept
	else
		result=nowait
	fi
	assert nowait ${result} "lock_acquire(TEST2) should not have slept, elapsed: ${elapsed}"
}

# Ensure TEST is held
{
	time=$(date +%s)
	lock_acquire TEST ${SLEEPTIME}
	assert 1 $? "lock TEST acquired but should be held"
	nowtime=$(date +%s)
	elapsed=$((${nowtime} - ${time}))
	if [ ${elapsed} -ge ${SLEEPTIME} ]; then
		result=slept
	else
		result=nowait
	fi
	assert slept ${result} "lock_acquire(TEST) should have slept, elapsed: ${elapsed}"
}

# Release TEST, but releasing return status is unreliable.
{
	lock_release TEST
	assert 0 $? "lock_release(TEST) did not succeed"
}

# Reacquire TEST to ensure it was released
{
	time=$(date +%s)
	lock_acquire TEST ${SLEEPTIME}
	assert 0 $? "lock_acquire failed"
	nowtime=$(date +%s)
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
	time=$(date +%s)
	lock_acquire TEST2 ${SLEEPTIME}
	assert 0 $? "lock_acquire failed"
	nowtime=$(date +%s)
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
