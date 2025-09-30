set -e
. ./common.sh
set +e

MASTERMNT=$(mktemp -d)

# Test noclobber support with shash_set
{
	assert_false shash_exists bucket key
	assert_true noclobber shash_set bucket key 1
	assert_false noclobber shash_set bucket key 2
	value=
	assert_true shash_get bucket key value
	assert 1 "${value}"
	assert_true shash_set bucket key 3
	value=
	assert_true shash_get bucket key value
	assert 3 "${value}"
	assert_true shash_unset bucket key
}

rm -rf "${MASTERMNT}"
exit 0
