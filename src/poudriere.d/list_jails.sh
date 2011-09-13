#!/bin/sh

usage() {
	echo "poudriere lsjail [options]"
	cat <<EOF

Options:
    -q          -- Do not print headers
EOF

	exit 1
}

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
. ${SCRIPTPREFIX}/common.sh


while getopts "q" FLAG; do
	case "${FLAG}" in
	q)
		NOHEADER=1
		;;
	*)
		usage
		;; 
	esac
done

[ "${NOHEADER}X" = "1X" ] || printf '%-20s %-13s %s\n' "JAILNAME" "VERSION" "ARCH"

zfs list -r -o poudriere:type,poudriere:name,poudriere:version,poudriere:arch | grep "^rootfs" | while read type name version arch; do
	printf '%-20s %-13s %s\n' "${name}" "${version}" "${arch}"
done
