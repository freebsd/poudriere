. ./common.sh

set_pipefail

MASTER_DATADIR=$(mktemp -dt datadir)
assert_true cd "${MASTER_DATADIR}"
assert_true add_relpath_var MASTER_DATADIR

MAX=20
FOOCOUNT=0
get_foo() {
	FOONAME="foo${FOOCOUNT:?}"
	FOOCOUNT="$((FOOCOUNT + 1))"
}
add_next_foo() {
	assert_true get_foo
	assert_true cd "${MASTER_DATADIR:?}"
	assert_true pkgqueue_add "build" "${FOONAME}"
	TEST_PMRTP_SKIP_BALANCE_POOL=1 assert_true pkgqueue_move_ready_to_pool
	assert_true cd "${MASTER_DATADIR:?}/pool"
}

pkgqueue_balance_pool_worker() {
	local tmp

	unset tmp
	while time_bounded_loop tmp 60; do
		assert_true pkgqueue_balance_pool
		sleep 0.1
	done
}

# Create a pool big enough for pkgqueue_get_next/find(1) to iterate through.
PRIORITIES_MAX=2000
PKGQUEUE_PRIORITIES="$(seq 0 ${PRIORITIES_MAX})"
# Ensure foo package ends up at the end. Need to do this before spawning
# the pkgqueue_balance_pool_worker.
FOOCOUNT=0
until [ "${FOOCOUNT}" -eq "${MAX}" ]; do
	get_foo
	assert_true pkgqueue_prioritize build "${FOONAME}" ${PRIORITIES_MAX}
done
FOOCOUNT=0

assert_true get_foo
assert_true pkgqueue_init

assert_true spawn_job pkgqueue_balance_pool_worker
assert_not '' "${spawn_job}"

assert_true cd "${MASTER_DATADIR:?}/pool"

until [ "${FOOCOUNT}" -eq "${MAX}" ]; do
	assert_true add_next_foo
	# The race happens here
	assert_true pkgqueue_get_next job_type pkgname
	assert "${FOONAME}" "${pkgname}"
	assert "build" "${job_type}"
	assert_true pkgqueue_clean_queue "${job_type}" "${pkgname}" "${clean_rdepends-}"
	assert_true pkgqueue_job_done "${job_type}" "${pkgname}"
done

assert_true pkgqueue_empty
assert_true pkgqueue_sanity_check 0
assert_true pkgqueue_get_next job_type pkgname
assert "" "${pkgname}"
assert "" "${job_type}"

assert_true cd "${POUDRIERE_TMPDIR:?}"
assert_ret 143 kill_job 2 "${spawn_job}"
rm -rf "${MASTER_DATADIR:?}"
