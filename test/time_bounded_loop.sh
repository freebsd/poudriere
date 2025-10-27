set -e
. ./common.sh
set +e

test_loop() {
	local timeout="$1"
	local tmp

	unset tmp
	while time_bounded_loop tmp "${timeout}"; do
		sleep 0.5
	done
}
assert_runs_less_than 5 test_loop 3
