#! /bin/sh

set -e
. common.sh
. ${SCRIPTPREFIX}/common.sh
set +e

foo="1 2 \$3"
getvar foo output
assert "${foo}" "${output}" "1. foo doesn't match"
assert "${foo}" "$(getvar foo)" "2. foo doesn't match"
ret=0
x=$(getvar nonexistent) || ret=$?
assert 1 "${ret}" "getvar nonexistent should fail"
assert "" "${x}" "getvar nonexistent should return empty string"
