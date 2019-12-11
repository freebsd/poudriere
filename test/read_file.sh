#! /bin/sh

set -e
. $(realpath $(dirname $0))/common.sh
. ${SCRIPTPREFIX}/include/util.sh
set +e

TMP=$(mktemp -u)
data=blah
read_file data "${TMP}"
assert_not 0 $? "read_file on missing file should not return 0"
assert '' "${data}" "read_file on missing file should be blank"
assert 0 "${_read_file_lines_read}" "_read_file_lines_read should be 0 on missing file"

echo "first" >> "${TMP}"
read_file data "${TMP}"
assert 'first' "${data}" "read_file on 1 line file should match"
assert 1 "${_read_file_lines_read}" "_read_file_lines_read should be 1"

data=blah
echo "second" >> "${TMP}"
read_file data "${TMP}"
assert $'first\nsecond' "${data}" "read_file on 2 line file should match"
assert 2 "${_read_file_lines_read}" "_read_file_lines_read should be 1"

data=blah
echo "third" >> "${TMP}"
read_file data "${TMP}"
assert $'first\nsecond\nthird' "${data}" "read_file on 3 line file should match"
assert 3 "${_read_file_lines_read}" "_read_file_lines_read should be 1"

rm -f "${TMP}"
exit 0
