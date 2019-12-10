#! /bin/sh

. common.sh
. ${SCRIPTPREFIX}/common.sh

foo="1 2 \$3"
getvar foo output
assert "${foo}" "${output}" "1. foo doesn't match"

assert "${foo}" "$(getvar foo)" "2. foo doesn't match"
