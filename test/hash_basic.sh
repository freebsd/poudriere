set -e
. ./common.sh
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
assert_true hash_set blah 45 foo
assert_true hash_set blah2 1 foo
assert_true hash_set blah2 1 foo
assert_false noclobber hash_set blah2 1 BAD
hash_get blah2 1 value
assert "foo" "${value}"
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

assert_true hash_vars vars '*' '*'
assert "blah2:1 foo:1 pkgname_origin:pkg_2_0" "${vars}"
value=
assert_true hash_remove blah2 1 value
assert "foo" "${value}"
assert_true hash_vars vars '*' '*'
assert "foo:1 pkgname_origin:pkg_2_0" "${vars}"
hash_unset foo 1
assert_true hash_vars vars '*' '*'
assert "pkgname_origin:pkg_2_0" "${vars}"
hash_unset pkgname_origin "pkg-2.0"
assert_false hash_vars vars '*' '*'
assert "" "${vars}"
assert_false hash_remove pkgname_origin "pkg-2.0"

assert_true hash_set blah key var
assert_true hash_isset blah key
assert_true hash_remove blah key
assert_false hash_isset blah key

exit 0
