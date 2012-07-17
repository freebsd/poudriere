#!/bin/sh

ORIGNAME=$1
PTNAME=$2
SLOT=$3
PORT=$4
PKGDIR=$5

BUILDER=1
SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
. ${SCRIPTPREFIX}/common.sh
ORIGFS=$(jail_get_fs ${ORIGNAME})
ORIGMNT=$(jail_get_base ${ORIGNAME})
JAILFS=${ORIGFS}
ARCH=$(zget arch)
VERSION=$(zget version)
JAILMNT="${POUDRIERE_DATA}/build/${ORIGNAME}-${PTNAME}/${SLOT}"
JAILFS="${ORIGFS}-${SLOT}"
JAILNAME="${ORIGNAME}-${SLOT}"

zfs clone -o mountpoint=${JAILMNT} \
	-o ${NS}:name=${JAILNAME} \
	-o ${NS}:type=rootfs \
	-o ${NS}:arch=${ARCH} \
	-o ${NS}:version=${VERSION} \
	${ORIGFS}@clean ${JAILFS}
zfs snapshot ${JAILFS}@clean

jail_start
prepare_jail
build_pkg ${PORT}
jail_stop
