set -e
. ./common.sh
set +e

MASTERMNT=$(mktemp -d)

set_test_contexts - '' '' <<-EOF
SHASH_USE_SHM	0 1
EOF

while get_test_context; do
	case "${SHASH_USE_SHM}" in
	1) assert_true shash_init_shm ;;
	esac

# Test noclobber support with shash_set
{
	assert_false shash_exists bucket key
	assert_true noclobber shash_set bucket key 1
	assert_false expect_error_on_stderr noclobber shash_set bucket key 2
	value=
	assert_true shash_get bucket key value
	assert 1 "${value}"
	assert_true shash_set bucket key 3
	value=
	assert_true shash_get bucket key value
	assert 3 "${value}"
	assert_true shash_unset bucket key
}

	case "${SHASH_USE_SHM}" in
	1) assert_true shash_cleanup_shm ;;
	esac
done

rm -rf "${MASTERMNT}"
exit 0
