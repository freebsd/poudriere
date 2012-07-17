#!/bin/sh

path=$1
port=$2

name=$(awk -v n=${port} '$1 == n { print $2 }' "${path}/cache")
rm -rf "${path}/pool/${name}"
find ${path}/pool -name ${name} -type f -delete
