#!/bin/sh

JAILMNT=$1
port=$2

name=$(awk -v n=${port} '$1 == n { print $2 }' "${JAILMNT}/cache")
rm -rf "${JAILMNT}/pool/${name}"
find ${JAILMNT}/pool -name ${name} -type f -delete
