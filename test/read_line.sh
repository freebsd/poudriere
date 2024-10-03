set -e
. common.sh
set +e

TMP=$(mktemp -u)
data=blah
read_line data "${TMP}"
assert_not 0 $? "read_line on missing file should not return 0"
assert '' "${data}" "read_line on missing file should be blank"
assert 'NULL' "${data-NULL}" "read_line on missing file should unset vars"

echo "first" >> "${TMP}"
read_line data "${TMP}"
assert 'first' "${data}" "read_line on 1 line file should match"

data=blah
echo "second" >> "${TMP}"
read_line data "${TMP}"
assert 'first' "${data}" "read_line on 2 line file should match"

data=blah
echo "third" >> "${TMP}"
read_line data "${TMP}"
assert 'first' "${data}" "read_line on 3 line file should match"

data=blah
echo "fourth" >> "${TMP}"
read_line '' "${TMP}"
assert "blah" "${data}" "read_line shouldn't have touched var"

rm -f "${TMP}"
