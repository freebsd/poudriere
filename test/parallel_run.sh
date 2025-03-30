set +e
. ./common.sh
set -e

set_test_contexts - '' '' <<-EOF
PARALLEL_JOBS 1 2 4 8 21
EOF

retval() {
	sleep 1
	return "$1"
}

while get_test_context; do
	capture_output_simple '' stderr

	TDIR="$(mktemp -d -t parallel_run)"
	{
		n=0
		max=20
		find "${TDIR}/" -type f -delete
		assert_true parallel_start
		until [ "${n}" -eq "${max}" ]; do
			assert_true parallel_run touch "${TDIR}/${n}"
			n=$((n + 1))
		done
		assert_true parallel_stop
		n=0
		until [ "${n}" -eq "${max}" ]; do
			assert_true [ -e "${TDIR}/${n}" ]
			n=$((n + 1))
		done
		find "${TDIR}/" -type f -delete
	}

	{
		n=0
		max=20
		ret=0
		assert_true parallel_start
		until [ "${n}" -eq "${max}" ]; do
			case "${n}" in
			0)
				assert_true parallel_run retval 40
				;;
			*)
				parallel_run retval 0 || ret="$?"
				;;
			esac
			n=$((n + 1))
		done
		parallel_stop || ret="$?"
		assert 40 "${ret}"
	}

	{
		n=0
		max=20
		ret=0
		assert_true parallel_start
		until [ "${n}" -eq "${max}" ]; do
			assert_true parallel_run :
			n=$((n + 1))
		done
		assert_true parallel_run retval 95
		parallel_stop || ret="$?"
		assert 95 "${ret}"
	}

	{
		n=0
		max=20
		ret=0
		assert_true parallel_start
		until [ "${n}" -eq "${max}" ]; do
			case "${n}" in
			5)
				assert_true parallel_run retval 5
				;;

			*)
				parallel_run : || ret="$?"
				;;
			esac
			n=$((n + 1))
		done
		assert_true parallel_run retval 95
		parallel_stop || ret="$?"
		assert 95 "${ret}"
	}
	rm -rf "${TDIR}"

	capture_output_simple_stop
	# No errors should have been seen.
	assert_file - "${stderr}" <<-EOF
	EOF
done
