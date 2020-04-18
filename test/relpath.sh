#! /bin/sh

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
RELATIVE_PATH_VARS="foo bar empty unset"
unset unset
empty=
foo="/tmp"
bar=".."

cd /
assert "tmp" "${foo}" 1
assert "." "${bar}" 2
assert "" "${empty}" 3
assert "" "${unset}" 4

cd etc
assert "../tmp" "${foo}" 5
assert ".." "${bar}" 6
assert "" "${empty}" 7
assert "" "${unset}" 8
