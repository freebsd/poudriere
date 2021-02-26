#!/bin/sh

#
# Copyright (c) 2015 Baptiste Daroussin <bapt@FreeBSD.org>
# All rights reserved.
# Copyright (c) 2021 Emmanuel Vadot <manu@FreeBSD.org>
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.

zsnapshot_check()
{

	[ ! -z "${SNAPSHOT_NAME}" ] || \
		err 1 "zsnapshot type requires a snapshot name (-S option)"
}

zsnapshot_prepare()
{

	zfs list ${ZPOOL}${ZROOTFS}/images >/dev/null 2>/dev/null || \
		zfs create -o compression=lz4 ${ZPOOL}${ZROOTFS}/images
	zfs list ${ZPOOL}${ZROOTFS}/images/work >/dev/null 2>/dev/null || \
		zfs create ${ZPOOL}${ZROOTFS}/images/work
	mkdir -p ${WRKDIR}/mnt
	if [ ! -z "${ORIGIN_IMAGE}" ]; then
		gzip -d < "${ORIGIN_IMAGE}" | \
			zfs recv ${ZPOOL}${ZROOTFS}/images/work/${JAILNAME}@previous
		zfs unmount ${ZPOOL}${ZROOTFS}/images/work/${JAILNAME}
	else
		zfs create ${ZPOOL}${ZROOTFS}/images/work/${JAILNAME}
		zfs unmount ${ZPOOL}${ZROOTFS}/images/work/${JAILNAME}
	fi
	zfs_zsnapshot=${ZPOOL}${ZROOTFS}/images/work/${JAILNAME}
	zfs set mountpoint=${WRKDIR}/mnt \
	       	${ZPOOL}${ZROOTFS}/images/work/${JAILNAME}
	zfs mount \
	       	${ZPOOL}${ZROOTFS}/images/work/${JAILNAME}
	if [ ! -z "${ORIGIN_IMAGE}" -a -f ${WRKDIR}/mnt/.version ]; then
		PREVIOUS_SNAPSHOT_VERSION=$(cat ${WRKDIR}/mnt/.version)
	fi
}

zsnapshot_build()
{

	do_clone -r ${WRKDIR}/world ${WRKDIR}/mnt
}

zsnapshot_generate()
{

	FINALIMAGE=${IMAGENAME}

	rm -f ${WRKDIR}/mnt/.version
	echo ${SNAPSHOT_NAME} > ${WRKDIR}/mnt/.version
	chmod 400 ${WRKDIR}/mnt/.version

	if [ ! -z "${ORIGIN_IMAGE}" ]; then
		zfs diff \
       			${ZPOOL}${ZROOTFS}/images/work/${JAILNAME}@previous \
			${ZPOOL}${ZROOTFS}/images/work/${JAILNAME} > ${WRKDIR}/modified.files
	fi

	zfs umount ${ZPOOL}${ZROOTFS}/images/work/${JAILNAME}
	zfs set mountpoint=none \
       		${ZPOOL}${ZROOTFS}/images/work/${JAILNAME}
	zfs snapshot ${ZPOOL}${ZROOTFS}/images/work/${JAILNAME}@${SNAPSHOT_NAME}
	zfs send ${ZPOOL}${ZROOTFS}/images/work/${JAILNAME}@${SNAPSHOT_NAME} > ${WRKDIR}/raw.img
	FULL_HASH=$(sha512 -q ${WRKDIR}/raw.img)
	# snapshot have some sparse regions, gzip is here to avoid them
	gzip -1 ${WRKDIR}/raw.img

	if [ ! -z "${ORIGIN_IMAGE}" ]; then
		zfs send -i previous ${ZPOOL}${ZROOTFS}/images/work/${JAILNAME}@${SNAPSHOT_NAME} > ${WRKDIR}/incr.img
		INCR_HASH=$(sha512 -q ${WRKDIR}/incr.img)
		gzip -1 ${WRKDIR}/incr.img
	fi

	if [ ! -z "${ORIGIN_IMAGE}" ]; then
		echo "{\"full\":{\"filename\":\"${FINALIMAGE}-${SNAPSHOT_NAME}.full.img.gz\", \"sha512\": \"${FULL_HASH}\"},\"incr\":{\"filename\":\"${FINALIMAGE}-${SNAPSHOT_NAME}.incr.img.gz\", \"sha512\": \"${INCR_HASH}\", \"previous\":\"${PREVIOUS_SNAPSHOT_VERSION}\", \"changed\":\"${FINALIMAGE}-${SNAPSHOT_NAME}.modified.files\"}, \"version\":\"${SNAPSHOT_NAME}\",\"name\":\"${FINALIMAGE}\"}" > ${WRKDIR}/manifest.json
	else
		echo "{\"full\":{\"filename\":\"${FINALIMAGE}-${SNAPSHOT_NAME}.full.img.gz\", \"sha512\": \"${FULL_HASH}\"}, \"version\":\"${SNAPSHOT_NAME}\",\"name\":\"${FINALIMAGE}\"}" > ${WRKDIR}/manifest.json
	fi

	if [ ! -z "${ORIGIN_IMAGE}" ]; then
		mv ${WRKDIR}/incr.img.gz "${OUTPUTDIR}/${FINALIMAGE}-${SNAPSHOT_NAME}.incr.img.gz"
		mv ${WRKDIR}/modified.files "${OUTPUTDIR}/${FINALIMAGE}-${SNAPSHOT_NAME}.modified.files"
	fi
	mv ${WRKDIR}/raw.img.gz "${OUTPUTDIR}/${FINALIMAGE}-${SNAPSHOT_NAME}.full.img.gz"
	mv ${WRKDIR}/manifest.json "${OUTPUTDIR}/${FINALIMAGE}-${SNAPSHOT_NAME}.manifest.json"
	ln -s ${FINALIMAGE}-${SNAPSHOT_NAME}.manifest.json ${WRKDIR}/${FINALIMAGE}-latest.manifest.json
	mv ${WRKDIR}/${FINALIMAGE}-latest.manifest.json "${OUTPUTDIR}/${FINALIMAGE}-latest.manifest.json"
}
