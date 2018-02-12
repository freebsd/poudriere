#! /bin/sh

. $(realpath $(dirname $0))/common.sh
. ${SCRIPTPREFIX}/include/util.sh
. ${SCRIPTPREFIX}/include/hash.sh
. ${SCRIPTPREFIX}/include/shared_hash.sh

assert_ret 1 hash_remove pkgname-origin "pkg-1.7" value
assert_ret 1 hash_isset pkgname-origin "pkg-1.7"
assert_ret 0 hash_unset pkgname-origin "pkg-1.7"
assert_ret 1 hash_get pkgname-origin "pkg-1.7" value
assert_ret 0 hash_set pkgname-origin "pkg-1.7" "ports-mgmt/pkg"
assert_ret 0 hash_set pkgname-origin "pkg-2.0" "ports-mgmt/pkg2.0"
assert_ret 0 hash_get pkgname-origin "pkg-1.7" value
assert "ports-mgmt/pkg" "${value}" "Removed value should match"
assert_ret 0 hash_get pkgname-origin "pkg-2.0" value
assert "ports-mgmt/pkg2.0" "${value}" "Removed value should match"
value=
assert_ret 0 hash_isset pkgname-origin "pkg-1.7"
assert_ret 0 hash_remove pkgname-origin "pkg-1.7" value
assert_ret 1 hash_isset pkgname-origin "pkg-1.7"
assert "ports-mgmt/pkg" "${value}" "Removed value should match"
value=
assert_ret 1 hash_get pkgname-origin "pkg-1.7" value

exit 0
