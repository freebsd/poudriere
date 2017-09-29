#! /bin/sh
#
# Test that (some) traps received while holding a lock are delayed until
# the lock is released.
# The same as locks_critical_section.sh but with a nested lock

SLEEPTIME=5

. common.sh
. ${SCRIPTPREFIX}/common.sh
. ${SCRIPTPREFIX}/include/util.sh

trap 'main_sigint=1' INT
trap 'main_sigterm=1' TERM
trap 'main_siginfo=1' INFO

# Ensure the basic traps work (for symmetry with later test)
main_sigint=0
kill -INT $$
assert 1 ${main_sigint} "INT should be trapped"
main_sigterm=0
kill -TERM $$
assert 1 ${main_sigterm} "TERM should be trapped"
main_siginfo=0
kill -INFO $$
assert 1 ${main_siginfo} "INFO should be trapped"

# lock_acquire does nothing with INFO currently
# lock_acquire delayed INT/TERM

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

	lock_have TEST
	assert 0 $? "lock_have(TEST) should be true"
}

# Acquire TEST2
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

	lock_have TEST2
	assert 0 $? "lock_have(TEST2) should be true"
}


# Now ensure that our traps *do not work*
main_sigint=0
kill -INT $$
assert 0 ${main_sigint} "INT should not be trapped in critical section"
main_sigterm=0
kill -TERM $$
assert 0 ${main_sigterm} "TERM should not be trapped in critical section"
main_siginfo=0
kill -INFO $$
assert 1 ${main_siginfo} "INFO should be trapped in critical section"
main_siginfo=0
lock_release TEST2

# The signals should not have been delivered on the nested lock_release
assert 0 ${main_sigint} "INT should not be delivered on nested lock_release"
assert 0 ${main_sigterm} "TERM should not be delivered on nested lock_release"
assert 0 ${main_siginfo} "INFO should not be delivered on lock_release"

lock_release TEST

# The signals should have been delivered on the final lock_release
assert 1 ${main_sigint} "INT should be delivered on lock_release"
assert 1 ${main_sigterm} "TERM should be delivered on lock_release"
assert 0 ${main_siginfo} "INFO should not be delivered on lock_release"
