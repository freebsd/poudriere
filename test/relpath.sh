set -e
. common.sh
. ${SCRIPTPREFIX}/common.sh
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

foo="/tmp"
bar=".."
for var in foo bar; do
	add_relpath_var "${var}"
done

cd /
assert "dev/null" "${DEVNULL}"
assert "/dev/null" "${DEVNULL_ABS}"
assert "tmp" "${foo}" 1
assert "." "${bar}" 2

cd etc
assert "../dev/null" "${DEVNULL}"
assert "/dev/null" "${DEVNULL_ABS}"
assert "../tmp" "${foo}" 5
assert ".." "${bar}" 6

cd /var/run
assert "../../dev/null" "${DEVNULL}"
assert "/dev/null" "${DEVNULL_ABS}"
assert "../../tmp" "${foo}" 5
assert "../.." "${bar}" 6
