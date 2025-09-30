set -e
. ./common.sh
set +e

MASTERMNT=$(mktemp -d)

# Test noclobber support with shash_write
{
	assert_false shash_exists bucket key
	noclobber shash_write bucket key <<-EOF
	1
	EOF
	assert 0 "$?"
	noclobber shash_write bucket key <<-EOF
	2
	EOF
	assert_not 0 "$?"
	value=
	assert_true shash_get bucket key value
	assert 1 "${value}"
	shash_write bucket key <<-EOF
	3
	EOF
	assert 0 "$?"
	value=
	assert_true shash_get bucket key value
	assert 3 "${value}"
	assert_true shash_unset bucket key
}

rm -rf "${MASTERMNT}"
exit 0
