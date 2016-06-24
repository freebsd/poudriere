#! /bin/sh

. $(realpath $(dirname $0))/common.sh
. ${SCRIPTPREFIX}/include/util.sh
. ${SCRIPTPREFIX}/include/hash.sh
. ${SCRIPTPREFIX}/include/shared_hash.sh

MASTERMNT=$(mktemp -d)

echo "Working on ${MASTERMNT}"
mkdir -p "${MASTERMNT}/.p/var/cache/"
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

rm -rf "${MASTERMNT}"
exit 0
