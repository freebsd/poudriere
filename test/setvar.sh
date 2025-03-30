set -e
. ./common.sh
set +e

foo=
assert_true setvar "foo" 1
assert 1 "${foo}"

bar=bad
foo="\${bar}"
assert_true setvar "foo" "${foo}"
assert "\${bar}" "${foo}"

bar=bad
foo='\${bar}'
assert_true setvar "foo" "${foo}"
assert '\${bar}' "${foo}"

tmp=$(mktemp -u)
bar=bad
foo='`touch ${tmp}`'
assert_false test -r "${tmp}"
assert_true setvar "foo" "${foo}"
assert_false test -r "${tmp}"
assert '`touch ${tmp}`' "${foo}"
assert_false test -r "${tmp}"
