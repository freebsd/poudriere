set -e
. ./common.sh
set +e

# XXX: This isn't testing symlinks yet
#dir1 dir2 - common reldir1 reldir2
dirs="\
/poudriere/data/.m/exp-10amd64-commit-test/ref/.p/var/cache /poudriere/data/.m/exp-10amd64-commit-test/ref/usr/ports/ports-mgmt/poudriere - ../../../../.p/var/cache \
/prefix/a/b/c /prefix/a/b - c \
/prefix/a/b /////prefix//a///b/c - .. \
/prefix/a/b/c /root/a - ../../prefix/a/b/c \
/prefix/a/b/c / - prefix/a/b/c \
/ /prefix/a/b/c - ../../../.. \
/tmp/../tmp /tmp - . \
/tmp/.. /tmp/../tmp/ - .. \
/tmp/../tmp/../tmp /tmp/../tmp/ - . \
/appdata/poudriere/data/.m/101x64-adm5-default/ref/var/db/ports /appdata/poudriere-etc/poudriere.d/101x64-adm5-options - ../../../poudriere/data/.m/101x64-adm5-default/ref/var/db/ports \
"

assert_dir() {
	local expected_rel_dir="$1"
	local expected_abs_dir="$2"
	assert "${expected_rel_dir}" "${PWD}"
	assert "${expected_abs_dir}" "$(realpath "${PWD}")"
}

set -- ${dirs}
while [ $# -gt 0 ]; do
	dir1="$1"
	dir2="$2"
	expected_reldir="$4"
	shift 4
	saved="$@"

	actual_reldir=$(relpath "${dir1}" "${dir2}")

	assert "${expected_reldir}" "${actual_reldir}" "1. dir1: ${dir1} dir2: ${dir2}"

	actual_reldir=
	relpath "${dir1}" "${dir2}" actual_reldir
	assert "${expected_reldir}" "${actual_reldir}" "2. dir1: ${dir1} dir2: ${dir2}"

	set -- ${saved}
done

cd /tmp
DEVNULL="../dev/null"
add_relpath_var DEVNULL
assert "../dev/null" "${DEVNULL}"
assert "/dev/null" "${DEVNULL_ABS}"

cd /
assert "dev/null" "${DEVNULL}"
assert "/dev/null" "${DEVNULL_ABS}"

cd /tmp
assert "../dev/null" "${DEVNULL}"
assert "/dev/null" "${DEVNULL_ABS}"

foo="$(mktemp -udt foo)"
mkdir -p "${foo}/FOO"
bar=".."
foo_real=$(realpath ${foo})
bar_real=$(realpath ${bar})
for var in foo bar; do
	add_relpath_var "${var}"
done
assert "${foo_real}" "${foo_ABS}"
assert "${bar_real}" "${bar_ABS}"
assert_true in_reldir foo assert_dir "${foo_real}" "${foo_ABS}"
assert_true in_reldir foo/FOO assert_dir "${foo_real}/FOO" "${foo_ABS}/FOO"
(
	cd "${foo_real}/FOO"
	assert_true in_reldir foo/FOO assert_dir "${foo_real}/FOO" "${foo_ABS}/FOO"
)
assert 0 "$?"
(
	cd "${foo_real}"
	assert_true in_reldir foo/FOO assert_dir "${foo_real}/FOO" "${foo_ABS}/FOO"
)
assert 0 "$?"
assert_true in_reldir bar assert_dir "${bar_real}" "${bar_ABS}"

cd /
assert "dev/null" "${DEVNULL}"
assert "/dev/null" "${DEVNULL_ABS}"
assert "${foo_real#/}" "${foo}" 1
assert "." "${bar}" 2
assert "${foo_real}" "${foo_ABS}"
assert "${bar_real}" "${bar_ABS}"
assert_true in_reldir foo assert_dir "${foo_real}" "${foo_ABS}"
assert_true in_reldir bar assert_dir "${bar_real}" "${bar_ABS}"

cd etc
assert "../dev/null" "${DEVNULL}"
assert "/dev/null" "${DEVNULL_ABS}"
assert "..${foo_real}" "${foo}" 5
assert ".." "${bar}" 6
assert "${foo_real}" "${foo_ABS}"
assert "${bar_real}" "${bar_ABS}"
assert_true in_reldir foo assert_dir "${foo_real}" "${foo_ABS}"
assert_true in_reldir bar assert_dir "${bar_real}" "${bar_ABS}"

cd /var/run
assert "../../dev/null" "${DEVNULL}"
assert "/dev/null" "${DEVNULL_ABS}"
assert "../..${foo_real}" "${foo}" 5
assert "../.." "${bar}" 6
assert "${foo_real}" "${foo_ABS}"
assert "${bar_real}" "${bar_ABS}"
assert_true in_reldir foo assert_dir "${foo_real}" "${foo_ABS}"
assert_true in_reldir bar assert_dir "${bar_real}" "${bar_ABS}"

rm -rf "${foo}"

cd "${POUDRIERE_TMPDIR:?}"
