#!/bin/sh

ORIGNAME=$1
PORT=$2
SLOT=$3

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
. ${SCRIPTPREFIX}/common.sh
ORIGFS=$(jail_get_fs ${ORIGNAME})
ORIGMNT=$(jail_get_base ${ORIGNAME})
JAILFS="${ORIGFS}/job-${SLOT}"
ARCH=$(zget arch)
VERSION=$(zget version)
JAILMNT="${ORIGMNT}/build/${SLOT}"
JAILFS="${ORIGFS}-${SLOT}"
JAILNAME="${ORIGNAME}-job-${SLOT}"

build_pkg ${PORT}
