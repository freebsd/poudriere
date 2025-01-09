set -e
. common.sh
set +e

foo="1 2 \$3"
getvar foo output
assert "${foo}" "${output}" "1. foo doesn't match"
assert "${foo}" "$(getvar foo)" "2. foo doesn't match"
assert_true issetvar foo
x=bad
x="$(getvar foo)"
assert 0 "$?"
assert "${foo}" "${x}"
x=bad
x="$(getvar foo -)"
assert 0 "$?"
assert "${foo}" "${x}"
x="$(getvar foo "")"
assert 0 "$?"
assert "${foo}" "${x}"
ret=0
x=bad
x="$(getvar nonexistent)" || ret="$?"
assert 1 "${ret}" "getvar nonexistent should fail"
assert "" "${x}" "getvar nonexistent should return empty string"
x="$(getvar nonexistent; echo .)"
assert "." "${x}" "getvar nonexistent should return empty string"
assert_false issetvar nonexistent
ret=0
x=bad
x="$(getvar nonexistent -)" || ret="$?"
assert 1 "${ret}" "getvar nonexistent should fail"
assert "" "${x}" "getvar nonexistent should return empty string"
ret=0
x=bad
x="$(getvar nonexistent -;echo .)" || ret="$?"
assert "." "${x}" "getvar nonexistent should return empty string"
ret=0
x=bad
x="$(getvar nonexistent "")" || ret="$?"
assert 1 "${ret}" "getvar nonexistent should fail"
assert "" "${x}" "getvar nonexistent should return empty string"
ret=0
x=bad
x="$(getvar nonexistent "";echo .)" || ret="$?"
assert "." "${x}" "getvar nonexistent should return empty string"
ret=0
x=bad
getvar nonexistent x || ret="$?"
assert 1 "${ret}" "getvar nonexistent should fail"
assert "" "${x}" "getvar nonexistent should return empty string"
assert "NULL" "${x-NULL}" "getvar nonexistent should return unset var"

assert_true incrvar nonexistent 2
assert "2" "${nonexistent}"
assert_true incrvar nonexistent
assert "3" "${nonexistent}"
assert_true decrvar nonexistent 2
assert "1" "${nonexistent}"
assert_true decrvar nonexistent
assert "0" "${nonexistent}"
unset nonexistent
assert_false decrvar nonexistent
