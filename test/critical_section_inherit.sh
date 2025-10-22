set -e
. ./common.sh
set +e

add_test_function test_critical_inherit
test_critical_inherit() {
	set -x
	bgjob() {
		set -x
		critical_start || exit 1
		ret=0
		x="$(
			critical_inherit
			{
				sleep 3
				echo .
			} | /usr/bin/wc -l
		)" || ret=$?
		case "${ret}" in
		0) ;;
		*)
			echo "Invalid wc -l exit status: ${ret} x='${x}'" >&2
			exit 1
			;;
		esac
		case "${x##* }" in
		1) ;;
		*)
			echo "Invalid wc -l value: '${x}'" >&2
			exit 1
			;;
		esac
		critical_end || exit 1
		exit 0
	}
	assert_true spawn_job bgjob
	assert_not '' "${spawn_jobid}"
	sleep 1
	assert_ret 143 kill_job 5 "%${spawn_jobid}"
}

run_test_functions
