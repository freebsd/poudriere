#!/bin/sh

JAILMNT=$1
PKGNAME=$2

case "${JAILMNT}" in
	/?*)
		;;
	*)
		echo "Invalid JAILMNT passed when cleaning pool" >&2
		exit 1
		;;
esac

if [ -z "${PKGNAME}" ]; then
	echo "Invalid PKGNAME passed when cleaning pool" >&2
	exit 1
fi

rm -rf "${JAILMNT}/pool/${PKGNAME}"
find ${JAILMNT}/pool -name "${PKGNAME}" -type f -delete
