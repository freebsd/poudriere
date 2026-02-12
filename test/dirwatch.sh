set -e
. ./common.sh
set +e

add_test_function test_dirwatch_basic_empty
test_dirwatch_basic_empty() {
	TMP=$(mktemp -dt dirwatch)
	assert_ret 124 timeout 2 dirwatch "${TMP}"
	rm -rf "${TMP}"
}

add_test_function test_dirwatch_basic_nonempty_timeout
test_dirwatch_basic_nonempty_timeout() {
	TMP=$(mktemp -dt dirwatch)
	:> "${TMP}/a"
	assert_ret 124 timeout 2 dirwatch "${TMP}"
	rm -rf "${TMP}"
}

add_test_function test_dirwatch_basic_nonempty_nflag_timeout
test_dirwatch_basic_nonempty_nflag_timeout() {
	TMP=$(mktemp -dt dirwatch)
	:> "${TMP}/a"
	assert_ret 0 timeout 2 dirwatch -n "${TMP}"
	rm -rf "${TMP}"
}

add_test_function test_dirwatch_basic_file_added
test_dirwatch_basic_file_added() {
	TMP=$(mktemp -dt dirwatch)
	:> "${TMP}/a"
	add_file() {
		assert_true cond_timedwait 5
		sleep 2
		:> "${TMP}/b"
		# just wait to make 143 exit simpler to expect
		sleep 60
	}
	assert_true spawn_job add_file
	assert_not '' "${spawn_job}"
	assert_true cond_signal
	assert_ret 0 timeout 5 dirwatch "${TMP}"
	assert_ret 143 kill_job 2 "${spawn_job:?}"
	rm -rf "${TMP}"
}

add_test_function test_dirwatch_basic_file_added_race
test_dirwatch_basic_file_added_race() {
	local n ret

	TMP=$(mktemp -dt dirwatch)
	MAX=100
	add_file() {
		n=0
		until [ "${n}" -eq "${MAX}" ]; do
			# try to create a file as dirwatch is starting up
			# but don't create one until it deletes the one
			# we add
			assert_true cond_timedwait 5
			:> "${TMP}/${n}"
			assert_true sleep "0.$(randint 1)$(randint 3)"
			n="$((n + 1))"
		done
		# just wait to make 143 exit simpler to expect
		sleep 60
	}
	assert_true spawn_job add_file
	assert_not '' "${spawn_job}"

	n=0
	until [ "${n}" -eq "${MAX}" ]; do
		n="$((n + 1))"
		# If this times out then a file got added between calling
		# and kevent blocking.
		assert_true dirempty "${TMP}"
		assert_true cond_signal
		ret=0
		assert_true sleep "0.$(randint 1)$(randint 3)"
		timeout 2 dirwatch "${TMP}" || ret="$?"
		case "${ret}" in
		0|124) assert "${ret}" "${ret}" "n=${n}" ;;
		*) assert "0|124" "${ret}" "n=${n}" ;;
		esac
		case "${ret}" in
		124) break ;;
		esac
		find "${TMP}" -mindepth 1 -type f -delete
	done
	assert "124" "${ret}"
	assert_ret 143 kill_job 0 "${spawn_job:?}"
	rm -rf "${TMP}"
}

add_test_function test_dirwatch_basic_file_added_race_nflag
test_dirwatch_basic_file_added_race_nflag() {
	local n

	TMP=$(mktemp -dt dirwatch)
	MAX=100
	add_file() {
		n=0
		until [ "${n}" -eq "${MAX}" ]; do
			# try to create a file as dirwatch is starting up
			# but don't create one until it deletes the one
			# we add
			assert_true cond_timedwait 5
			:> "${TMP}/${n}"
			assert_true sleep "0.$(randint 1)$(randint 3)"
			n="$((n + 1))"
		done
		# just wait to make 143 exit simpler to expect
		sleep 60
	}
	assert_true spawn_job add_file
	assert_not '' "${spawn_job}"

	n=0
	until [ "${n}" -eq "${MAX}" ]; do
		n="$((n + 1))"
		# If this times out then a file got added between calling
		# and kevent blocking.
		assert_true dirempty "${TMP}"
		assert_true cond_signal
		assert_true sleep "0.$(randint 1)$(randint 3)"
		assert_ret 0 timeout 2 dirwatch -n "${TMP}"
		find "${TMP}" -mindepth 1 -type f -delete
	done
	assert_ret 143 kill_job 0 "${spawn_job:?}"
	rm -rf "${TMP}"
}

run_test_functions
