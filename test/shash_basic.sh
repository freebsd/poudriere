#! /bin/sh

. $(realpath $(dirname $0))/common.sh
. ${SCRIPTPREFIX}/include/util.sh
. ${SCRIPTPREFIX}/include/hash.sh
. ${SCRIPTPREFIX}/include/shared_hash.sh

MASTERMNT=$(mktemp -d)

echo "Working on ${MASTERMNT}"
SHASH_VAR_PATH="${MASTERMNT}"
assert_ret 1 shash_remove pkgname-origin "pkg-1.7" value
assert_ret 0 shash_unset pkgname-origin "pkg-1.7"
assert_ret 1 shash_get pkgname-origin "pkg-1.7" value
assert_ret 0 shash_set pkgname-origin "pkg-1.7" "ports-mgmt/pkg"
assert_ret 0 shash_get pkgname-origin "pkg-1.7" value
assert "ports-mgmt/pkg" "${value}" "Removed value should match"
value=
assert_ret 0 shash_remove pkgname-origin "pkg-1.7" value
assert "ports-mgmt/pkg" "${value}" "Removed value should match"
value=
assert_ret 1 shash_get pkgname-origin "pkg-1.7" value

# Test globbing
{
	assert_ret 1 shash_get pkgname-origin "pkg-*" value
	assert_ret 0 shash_set pkgname-origin "pkg-1.7" "ports-mgmt/pkg"
	assert_ret 0 shash_get pkgname-origin "pkg-1.7" value
	value=
	assert_ret 0 shash_get pkgname-origin "pkg-*" value
	assert "ports-mgmt/pkg" "${value}" "Removed value should match"
	assert_ret 0 shash_set pkgname-origin "pkg-2.0" "ports-mgmt/pkg2"
	value=
	assert_ret 0 shash_get pkgname-origin "pkg-*" value
	assert "ports-mgmt/pkg ports-mgmt/pkg2" "${value}" "Globbing shash_get should match"
	assert_ret 0 shash_unset pkgname-origin "pkg-*"
	assert_ret 1 shash_get pkgname-origin "pkg-1.7" value
	assert_ret 1 shash_get pkgname-origin "pkg-2.0" value
	assert_ret 1 shash_get pkgname-origin "pkg-*" value

	assert_ret 1 shash_get pkgname-origin "notfound-*" value
	assert "" "${value}" "globbed missing value"

	assert_ret 1 shash_get pkgname-origin "*-notfound" value
	assert "" "${value}" "globbed missing value"
}

# Test shash_remove_var
{
	assert_ret 0 shash_set foo-origin "a" A
	assert_ret 0 shash_set foo-origin "b" B
	assert_ret 0 shash_set foo-origin "c" C
	assert_ret 0 shash_set foo-origin "d" D
	assert_ret 0 shash_get foo-origin "a" value
	assert "A" "${value}" "A value should match"
	assert_ret 0 shash_get foo-origin "b" value
	assert "B" "${value}" "B value should match"
	assert_ret 0 shash_get foo-origin "c" value
	assert "C" "${value}" "C value should match"
	assert_ret 0 shash_get foo-origin "d" value
	assert "D" "${value}" "D value should match"

	assert_ret 0 shash_remove_var foo-origin
	assert_ret 1 shash_get foo-origin "a" value
	assert_ret 1 shash_get foo-origin "b" value
	assert_ret 1 shash_get foo-origin "c" value
	assert_ret 1 shash_get foo-origin "d" value

	assert_ret 1 shash_get pkgname-origin "pkg-1.7" value
	assert_ret 0 shash_set pkgname-origin "pkg-1.7" "ports-mgmt/pkg"
	assert_ret 0 shash_get pkgname-origin "pkg-1.7" value
	assert "ports-mgmt/pkg" "${value}" "pkg should match afer shash_remove_var"
}

rm -rf "${MASTERMNT}"
exit 0
