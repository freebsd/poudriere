#!/bin/sh

JAILMNT=$1
PKGNAME=$2

rm -rf "${JAILMNT}/pool/${PKGNAME}"
find ${JAILMNT}/pool -name "${PKGNAME}" -type f -delete
