#!/bin/sh

JAILMNT=$1
PKGNAME=$2

case "${JAILMNT}" in
	/?*)
		;;
	*)
		echo "Invalid JAILMNT"
		exit 1
		;;
esac

if [ -z "${PKGNAME}" ]; then
	echo "Invalid PKGNAME"
	exit 1
fi

rm -rf "${JAILMNT}/pool/${PKGNAME}"
find ${JAILMNT}/pool -name "${PKGNAME}" -type f -delete
