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

rm -rf "${JAILMNT}/poudriere/pool/${PKGNAME}"
find ${JAILMNT}/poudriere/pool -name "${PKGNAME}" -type f -delete
