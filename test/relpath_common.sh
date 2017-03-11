#! /bin/sh

. common.sh
. ${SCRIPTPREFIX}/common.sh


# XXX: This isn't testing symlinks yet
#dir1 dir2 - common reldir1 reldir2
dirs="\
/prefix/a/b/c /prefix/a/b - /prefix/a/b c . \
/prefix/a/b /prefix/a/b/c - /prefix/a/b . c \
/prefix/a/b/c /root/a - / prefix/a/b/c root/a \
/prefix/a/b/c / - / prefix/a/b/c . \
/ /prefix/a/b/c - / . prefix/a/b/c \
/tmp/../tmp /tmp - /tmp . . \
/tmp/.. /tmp/../tmp/ - / . tmp \
/tmp/../tmp/../tmp /tmp/../tmp/ - /tmp . . \
/appdata/poudriere/data/.m/101x64-adm5-default/ref/var/db/ports /appdata/poudriere-etc/poudriere.d/101x64-adm5-options - /appdata poudriere/data/.m/101x64-adm5-default/ref/var/db/ports poudriere-etc/poudriere.d/101x64-adm5-options \
"

set -- ${dirs}
while [ $# -gt 0 ]; do
	dir1="$1"
	dir2="$2"
	expected_common="$4"
	expected_reldir1="$5"
	expected_reldir2="$6"
	shift 6
	saved="$@"

	set -- $(relpath_common "${dir1}" "${dir2}")
	actual_common="$1"
	actual_reldir1="$2"
	actual_reldir2="$3"

	assert "${expected_common}" "${actual_common}" "(common) dir1: '${dir1}' dir2: '${dir2}'"
	assert "${expected_reldir1}" "${actual_reldir1}" "(reldir1) dir1: '${dir1}' dir2: '${dir2}'"
	assert "${expected_reldir2}" "${actual_reldir2}" "(reldir2) dir1: '${dir1}' dir2: '${dir2}'"

	set -- ${saved}
done
