#!/bin/sh
#
# Copyright (c) 2018-2021 Allan Jude <allanjude@FreeBSD.org>
# Copyright (c) 2019 Marie Helene Kvello-Aune <freebsd@mhka.no>
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

_zfs_writereplicationstream()
{

	# Arguments:
	# $1: snapshot to recursively replicate
	# $2: Image name to write replication stream to
	[ $# -eq 2 ] || eargs _zfs_writereplicationstream snapshot_from image_to
	msg "Creating replication stream"
	zfs send ${ZFS_SEND_FLAGS} "$1" > "${OUTPUTDIR}/$2" ||
	    err 1 "Failed to save ZFS replication stream"
}

zfs_check()
{
	zroot="${ZFS_POOL_NAME}.$(jot -r 1 1000000000)"

	[ -n "${IMAGESIZE}" ] || err 1 "Please specify the imagesize"
	[ -n "${ZFS_POOL_NAME}" ] || err 1 "Please specify a pool name"
	zpool list -Ho name ${zroot} >/dev/null 2>&1 && \
		err 1 "Temporary pool name already exists"
	case "${IMAGENAME}" in
	''|*[!A-Za-z0-9_.-]*)
		err 1 "Name can only contain alphanumeric characters"
		;;
	esac
	[ -f "${mnt}/boot/kernel/kernel" ] || \
	    err 1 "The ${MEDIATYPE} media type requires a jail with a kernel"
	if [ -n "${ORIGIN_IMAGE}" ]; then
		[ -z "${SNAPSHOT_NAME}" ] || err 1 \
			"You must specify the snapshot name (-S) when using -i"
	fi
}

zfs_prepare()
{

	truncate -s ${IMAGESIZE} ${WRKDIR}/raw.img
	md=$(/sbin/mdconfig ${WRKDIR}/raw.img)

	msg "Creating temporary ZFS pool"
	zpool create \
		-O mountpoint=/${ZFS_POOL_NAME} \
		-O canmount=noauto \
		-O checksum=sha512 \
		-O compression=on \
		-O atime=off \
		-t ${zroot} \
		-R ${WRKDIR}/world ${ZFS_POOL_NAME} /dev/${md} || exit

	if [ -n "${ORIGIN_IMAGE}" ]; then
		msg "Importing previous ZFS Datasets"
		zfs recv -F ${zroot} < "${ORIGIN_IMAGE}"
	else
		msg "Creating ZFS Datasets"
		zfs create -o mountpoint=none ${zroot}/${ZFS_BEROOT_NAME}
		zfs create -o mountpoint=/ ${zroot}/${ZFS_BEROOT_NAME}/${ZFS_BOOTFS_NAME}
		zfs create -o mountpoint=/tmp -o exec=on -o setuid=off ${zroot}/tmp
		zfs create -o mountpoint=/usr -o canmount=off ${zroot}/usr
		zfs create ${zroot}/usr/home
		zfs create -o setuid=off ${zroot}/usr/ports
		zfs create ${zroot}/usr/src
		zfs create ${zroot}/usr/obj
		zfs create -o mountpoint=/var -o canmount=off ${zroot}/var
		zfs create -o exec=off -o setuid=off ${zroot}/var/audit
		zfs create -o exec=off -o setuid=off ${zroot}/var/crash
		zfs create -o exec=off -o setuid=off ${zroot}/var/log
		zfs create -o atime=on ${zroot}/var/mail
		zfs create -o setuid=off ${zroot}/var/tmp
		chmod 1777 ${WRKDIR}/world/tmp ${WRKDIR}/world/var/tmp
	fi
}

zfs_build()
{
	if [ -z "${ORIGIN_IMAGE}" ]; then
		cat >> ${WRKDIR}/world/boot/loader.conf <<-EOF
		zfs_load="YES"
		EOF
		if [ -n "${SWAPSIZE}" -a "${SWAPSIZE}" != "0" ]; then
			cat >> ${WRKDIR}/world/etc/fstab <<-EOSWAP
			/dev/gpt/swapspace none swap sw 0 0
			EOSWAP
		fi
	fi
}

zfs_generate()
{

	: ${SNAPSHOT_NAME:=$IMAGENAME}
	FINALIMAGE=${IMAGENAME}.img
	zpool set bootfs=${zroot}/${ZFS_BEROOT_NAME}/${ZFS_BOOTFS_NAME} ${zroot}
	zpool set autoexpand=on ${zroot}
	zfs set canmount=noauto ${zroot}/${ZFS_BEROOT_NAME}/${ZFS_BOOTFS_NAME}

	SNAPSPEC="${zroot}@${SNAPSHOT_NAME}"

	msg "Creating snapshot(s) for image generation"
	zfs snapshot -r "$SNAPSPEC"

	## If we are creating a send stream, we need to do it before we export
	## the pool. Call the function to export the replication stream(s) here.
	## We do the inner case twice so we create a +full and a +be in one run.
	case "$1" in
	send)
		FINALIMAGE=${IMAGENAME}.*.zfs
		case "${MEDIAREMAINDER}" in
		*full*|send|zfs)
			_zfs_writereplicationstream "${SNAPSPEC}" "${IMAGENAME}.full.zfs"
			;;
		esac
		case "${MEDIAREMAINDER}" in
		*be*)
			BESNAPSPEC="${zroot}/${ZFS_BEROOT_NAME}/${ZFS_BOOTFS_NAME}@${SNAPSHOT_NAME}"
			_zfs_writereplicationstream "${BESNAPSPEC}" "${IMAGENAME}.be.zfs"
			;;
		esac
		;;
	esac

	## When generating a disk image, we need to export the pool first.
	zpool export ${zroot}
	zroot=
	/sbin/mdconfig -d -u ${md#md}
	md=

	case "$1" in
	raw)
		mv "${WRKDIR}/raw.img" "${OUTPUTDIR}/${FINALIMAGE}"
		;;
	gpt|zfs)
		espfilename=$(mktemp /tmp/efiboot.XXXXXX)
		zfsimage=${WRKDIR}/raw.img
		make_esp_file ${espfilename} 10 ${mnt}/boot/loader.efi

		if [ ${SWAPSIZE} != "0" ]; then
			SWAPCMD="-p freebsd-swap/swapspace::${SWAPSIZE}"
			if [ $SWAPBEFORE -eq 1 ]; then
				SWAPFIRST="$SWAPCMD"
			else
				SWAPLAST="$SWAPCMD"
			fi
		fi
		if [ "${arch}" == "amd64" ] || [ "${arch}" == "i386" ]; then
			pmbr="-b ${mnt}/boot/pmbr"
			gptbootfilename=$(mktemp /tmp/gptzfsboot.XXXXXX)
			cp "$mnt"/boot/gptzfsboot "$gptbootfilename"
			truncate -s 512k "$gptbootfilename"
			gptboot="-p freebsd-boot:=${gptbootfilename}"
		fi
		mkimg -s gpt ${pmbr} \
			  -p efi/efiboot0:=${espfilename} \
			  ${gptboot} \
			  ${SWAPFIRST} \
			  -p freebsd-zfs:=${zfsimage} \
			  ${SWAPLAST} \
			  -o "${OUTPUTDIR}/${FINALIMAGE}"
		rm -rf ${espfilename}
		rm -f "$gptbootfilename"
		;;
	esac
}
