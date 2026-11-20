set -e
. ./common.sh
set +e

# Create a build dir with a .data.mini.json naming it.
make_build() {
	[ "$#" -eq 2 ] || eargs make_build log_path_jail buildname
	local mb_log_path_jail="$1"
	local mb_buildname="$2"

	assert_true mkdir -p "${mb_log_path_jail:?}/${mb_buildname:?}"
	echo "{\"buildname\":\"${mb_buildname}\"}" > \
	    "${mb_log_path_jail:?}/${mb_buildname:?}/.data.mini.json"
}

# Mixed hex and date buildnames, with latest-done set.
# The running build is neither the lexically last nor latest-done.
make_builds() {
	[ "$#" -eq 1 ] || eargs make_builds log_path_jail
	local mbs_log_path_jail="$1"
	local mbs_buildname

	for mbs_buildname in 082d07dd3349 ce97aa4dd1d9 \
	    20261107_aaaaaaaaaaaa 20261115_481479f3014c \
	    20261119_839b87a8368c; do
		make_build "${mbs_log_path_jail:?}" "${mbs_buildname}"
	done
	assert_true mkdir -p "${mbs_log_path_jail:?}/latest-per-pkg"
	assert_true ln -s 20261115_481479f3014c \
	    "${mbs_log_path_jail:?}/latest-done"
}

# Build objects in these fixtures have no commas, so this gives one line
# per build key.
jail_json_lines() {
	[ "$#" -eq 1 ] || eargs jail_json_lines log_path_jail
	local jjl_log_path_jail="$1"

	tr ',' '\n' < "${jjl_log_path_jail:?}/.data.json"
}

# The jail_json_lines output expected for make_builds, without "latest".
expected_builds() {
	cat <<-EOF
	{"builds":{
	"082d07dd3349":{"buildname":"082d07dd3349"}
	"20261107_aaaaaaaaaaaa":{"buildname":"20261107_aaaaaaaaaaaa"}
	"20261115_481479f3014c":{"buildname":"20261115_481479f3014c"}
	"20261119_839b87a8368c":{"buildname":"20261119_839b87a8368c"}
	"ce97aa4dd1d9":{"buildname":"ce97aa4dd1d9"}
	}}
	EOF
}

add_test_function test_build_jail_json_latest_running
test_build_jail_json_latest_running() {
	local log_path_jail

	log_path_jail="$(mktemp -dt build_jail_json)"
	make_builds "${log_path_jail:?}"
	assert_true ln -s 20261119_839b87a8368c "${log_path_jail:?}/latest"
	assert_true _build_jail_json "${log_path_jail:?}"
	jail_json_lines "${log_path_jail:?}" > "${log_path_jail:?}/have"
	assert_file_unordered - "${log_path_jail:?}/have" <<-EOF
	$(expected_builds)
	"latest":"20261119_839b87a8368c"
	EOF
	assert_true rm -rf "${log_path_jail:?}"
}

add_test_function test_build_jail_json_latest_missing
test_build_jail_json_latest_missing() {
	local log_path_jail

	log_path_jail="$(mktemp -dt build_jail_json)"
	make_builds "${log_path_jail:?}"
	assert_true _build_jail_json "${log_path_jail:?}"
	jail_json_lines "${log_path_jail:?}" > "${log_path_jail:?}/have"
	assert_file_unordered - "${log_path_jail:?}/have" <<-EOF
	$(expected_builds)
	EOF
	assert_true rm -rf "${log_path_jail:?}"
}

add_test_function test_build_jail_json_latest_dangling
test_build_jail_json_latest_dangling() {
	local log_path_jail

	log_path_jail="$(mktemp -dt build_jail_json)"
	make_builds "${log_path_jail:?}"
	assert_true ln -s 20261120_000000000000 "${log_path_jail:?}/latest"
	assert_true _build_jail_json "${log_path_jail:?}"
	jail_json_lines "${log_path_jail:?}" > "${log_path_jail:?}/have"
	assert_file_unordered - "${log_path_jail:?}/have" <<-EOF
	$(expected_builds)
	EOF
	assert_true rm -rf "${log_path_jail:?}"
}

# A build that just started has an empty .data.mini.json.
add_test_function test_build_jail_json_latest_starting
test_build_jail_json_latest_starting() {
	local log_path_jail

	log_path_jail="$(mktemp -dt build_jail_json)"
	make_builds "${log_path_jail:?}"
	assert_true mkdir -p "${log_path_jail:?}/20261120_000000000000"
	assert_true touch "${log_path_jail:?}/20261120_000000000000/.data.mini.json"
	assert_true ln -s 20261120_000000000000 "${log_path_jail:?}/latest"
	assert_true _build_jail_json "${log_path_jail:?}"
	jail_json_lines "${log_path_jail:?}" > "${log_path_jail:?}/have"
	assert_file_unordered - "${log_path_jail:?}/have" <<-EOF
	$(expected_builds)
	EOF
	assert_true rm -rf "${log_path_jail:?}"
}

run_test_functions
