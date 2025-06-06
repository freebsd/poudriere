# Test that (some) traps received while holding a lock are delayed until
# the lock is released.

SLEEPTIME=5

set -e
. ./common.sh
set +e

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

{
	# Acquire TEST
	{
		time=$(clock -monotonic)
		lock_acquire TEST ${SLEEPTIME}
		assert 0 $? "lock_acquire failed"
		critical_start
		assert 0 "$?" "critical_start"
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

	# Now ensure that our traps *do not work*
	main_sigint=0
	kill -INT $$
	assert 0 ${main_sigint} "INT should not be trapped in critical section"
	main_sigterm=0
	kill -TERM $$
	assert 0 ${main_sigterm} "TERM should not be trapped in critical section"
	main_siginfo=0
	kill -INFO $$
	assert 0 ${main_siginfo} "INFO should not be trapped in critical section"
	main_siginfo=0

	lock_release TEST
	critical_end
	assert 0 "$?" "critical_end"

	# The signals should have been delivered on the lock_release
	assert 1 ${main_sigint} "INT should be delivered on lock_release"
	assert 1 ${main_sigterm} "TERM should be delivered on lock_release"
	assert 1 ${main_siginfo} "INFO should be delivered on lock_release"
}

# Forking with a lock does bad things
{
	lock_acquire TEST 0
	assert 0 "$?" "lock_acquire"

	set -m
	(
		_spawn_wrapper :
		lock_have TEST
		assert_not 0 "$?" "child should not have lock TEST"
		sleep 300
	) &
	set +m
	jobs -l
	get_job_id "$!" bgjob

	sleep 2
	kill_job 10 "%${bgjob}"
	assert 0 "$?" "kill bgpid - it should exit on TERM rather than wait"

	lock_release TEST
	assert 0 "$?" "lock_release"
}

find "${POUDRIERE_TMPDIR:?}/" -name "lock--*" -delete
