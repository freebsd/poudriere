OVERLAYS=""
TESTPORT="ports-mgmt/pkg"
LISTPORTS="${TESTPORT}"
. ./common.bulk.sh

set_test_contexts - '' '' <<-EOF
- MAX_MEMORY 1 ""
- MAX_MEMORY_BYTES $((20 * 1024 * 1024)) $((512 * 1024 * 1024)) ""
- MAX_FILES 10 100 ""
EOF
while get_test_context; do
	set_poudriere_conf <<-EOF
	${MAX_MEMORY:+MAX_MEMORY="${MAX_MEMORY-}"}
	${MAX_MEMORY_BYTES:+MAX_MEMORY_BYTES="${MAX_MEMORY_BYTES-}"}
	${MAX_FILES:+MAX_FILES="${MAX_FILES-}"}
	EOF

	# testport will keep old packages so we need to clean out everything
	# before doing the first run to ensure it all builds.
	do_pkgclean -y -A
	assert 0 $? "Pkgclean should pass"
	echo "-----" | tee /dev/stderr

	EXPECTED_QUEUED="${TESTPORT}:listed"
	EXPECTED_LISTED="${TESTPORT}"
	EXPECTED_TOBUILD="${EXPECTED_QUEUED}"
	EXPECTED_BUILT=
	do_testport -n ${TESTPORT}
	assert 0 "$?" "testport dry-run should pass"
	assert_bulk_queue_and_stats
	assert_bulk_build_results
	echo "-----" | tee /dev/stderr

	EXPECTED_BUILT="${EXPECTED_TOBUILD}"
	EXPECTED_FAILED=
	exp_ret=0
	case "${MAX_MEMORY_BYTES-}" in
	"$((20 * 1024 * 1024))")
		exp_ret=1
		EXPECTED_BUILT=
		EXPECTED_FAILED="${EXPECTED_TOBUILD}"
		;;
	esac
	# MAX_FILES default is 8192
	case "${MAX_FILES-}" in
	"") MAX_FILES=8192 ;;
	esac
	case "${MAX_FILES-}" in
	10)
		exp_ret=1
		EXPECTED_BUILT=
		EXPECTED_FAILED="${EXPECTED_TOBUILD}"
		;;
	esac
	do_testport ${TESTPORT}
	assert "${exp_ret}" "$?" "testport exit status"
	assert_bulk_queue_and_stats
	assert_bulk_build_results
	echo "-----" | tee /dev/stderr

	# We simply check the logs for the ulimit -a output in the
	# port build.
	_log_path log || err 99 "Unable to determine logdir"
	assert_true [ -e "${log}/logs/pkg-"*.log ]
	case "${MAX_FILES:+set}" in
	set)
		assert_true grep "^open files.*\<${MAX_FILES}\$" \
		    "${log}/logs/pkg-"*.log
		;;
	*)
		assert_true grep "^open files.*unlimited\$" \
		    "${log}/logs/pkg-"*.log
		;;
	esac
	case "${MAX_MEMORY:+set}" in
	set)
		max_memory_kbytes="$((MAX_MEMORY * 1024 * 1024))"
		assert_true grep "^virtual mem size.*\<${max_memory_kbytes}\$" \
		    "${log}/logs/pkg-"*.log
		;;
	*)
		case "${MAX_MEMORY_BYTES:+set}" in
		set)
			max_memory_kbytes="$((MAX_MEMORY_BYTES / 1024))"
			assert_true grep "^virtual mem size.*\<${max_memory_kbytes}\$" \
			    "${log}/logs/pkg-"*.log
			;;
		*)
			assert_true grep "^virtual mem size.*unlimited\$" \
			    "${log}/logs/pkg-"*.log
			;;
		esac
		;;
	esac
done
