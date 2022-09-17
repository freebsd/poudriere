set -e
. common.sh
. ${SCRIPTPREFIX}/common.sh
. ${SCRIPTPREFIX}/include/util.sh
. ${SCRIPTPREFIX}/include/hash.sh
. ${SCRIPTPREFIX}/include/shared_hash.sh
set +e

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

assert_ret 1 hash_isset_var 'blah'
hash_set blah 1 foo
hash_set blah 2 foo
hash_set blah 3 foo
hash_set blah 45 foo
hash_set blah2 1 foo
hash_set foo 1 foo
assert_ret 0 hash_isset_var 'blah'
assert_ret 0 hash_unset_var 'blah'
assert_ret 1 hash_isset blah 1
assert_ret 1 hash_isset blah 2
assert_ret 1 hash_isset blah 3
assert_ret 1 hash_isset blah 45
assert_ret 0 hash_isset blah2 1
assert_ret 0 hash_isset foo 1
assert_ret 1 hash_isset_var 'blah'

exit 0
