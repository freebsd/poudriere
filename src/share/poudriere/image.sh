#!/bin/sh
# 
# Copyright (c) 2015 Baptiste Daroussin <bapt@FreeBSD.org>
# All rights reserved.
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

usage() {
	[ $# -gt 0 ] && echo "Missing: $@" >&2
	cat << EOF
poudriere image [parameters] [options]

Parameters:
    -o outputdir    -- Image destination directory
    -j jail         -- Jail
    -p portstree    -- Ports tree
    -z set          -- Set
    -s size         -- Set the image size
    -n imagename    -- the name of the generated image
    -h hostname     -- the image hostname
    -t type         -- Type of image can be one of (default iso+zmfs):
                    -- iso, iso+mfs, iso+zmfs, usb, usb+mfs, usb+zmfs,
                       rawdisk, zrawdisk, tar, firmware, rawfirmware
    -X exclude      -- file containing the list in cpdup format
    -f packagelist  -- list of packages to install
    -c extradir     -- the content of the directory will copied in the target
EOF
	exit 1
}

delete_image() {
	[ ! -f "${excludelist}" ] || rm -f ${excludelist}
	[ -z "${zroot}" ] || zpool destroy -f ${zroot}
	[ -z "${md}" ] || /sbin/mdconfig -d -u ${md#md}

	destroyfs ${WRKDIR} image
}

cleanup_image() {
	msg "Error while create image. cleaning up." >&2
	delete_image
}

. ${SCRIPTPREFIX}/common.sh

while getopts "o:j:p:z:n:t:X:f:c:h:s:" FLAG; do
	case "${FLAG}" in
		o)
			OUTPUTDIR=${OPTARG}
			;;
		j)
			JAILNAME=${OPTARG}
			;;
		p)
			PTNAME=${OPTARG}
			;;
		t)
			MEDIATYPE=${OPTARG}
			case ${MEDIATYPE} in
			iso|iso+mfs|iso+zmfs|usb|usb+mfs|usb+mfs) ;;
			rawdisk|zrawdisk|tar|firmware|rawfirmware) ;;
			*) err 1 "invalid mediatype: ${MEDIATYPE}"
			esac
			;;
		n)
			IMAGENAME=${OPTARG}
			;;
		h)
			HOSTNAME=${OPTARG}
			;;
		X)
			[ -f "${OPTARG}" ] || err 1 "No such exclude list ${OPTARG}"
			EXCLUDELIST=$(realpath ${OPTARG})
			;;
		z)
			[ -n "${OPTARG}" ] || err 1 "Empty set name"
			SETNAME="${OPTARG}"
			;;
		s)
			IMAGESIZE="${OPTARG}"
			;;
		f)
			[ -f "${OPTARG}" ] || err 1 "No such package list: ${OPTARG}"
			PACKAGELIST=$(realpath ${OPTARG})
			;;
		c)
			[ -d "${OPTARG}" ] || err 1 "No such extract directory: ${OPTARG}"
			EXTRADIR=$(realpath ${OPTARG})
			;;
		*)
			echo "Unknown flag '${FLAG}'"
			usage
			;;
	esac
done

saved_argv="$@"
shift $((OPTIND-1))
post_getopts

: ${MEDIATYPE:=iso+zmfs}
: ${PTNAME:=default}

[ -n "${JAILNAME}" ] || usage

: ${OUTPUTDIR:=${POUDRIERE_DATA}/images/}
: ${IMAGENAME:=poudriereimage}
MASTERNAME=${JAILNAME}-${PTNAME}${SETNAME:+-${SETNAME}}

# CFG_SIZE set /etc and /var ramdisk size and /cfg partition size
# DATA_SIZE set /data partition size
CFG_SIZE="32m"
DATA_SIZE="32m"

# Limitation on isos
case "${IMAGENAME}" in
''|*[!A-Za-z0-9]*)
	err 1 "Name can only contain alphanumeric characters"
	;;
esac

mkdir -p ${OUTPUTDIR}

jail_exists ${JAILNAME} || err 1 "The jail ${JAILNAME} does not exists"
case "${MEDIATYPE}" in
usb)
	[ -n "${IMAGESIZE}" ] || err 1 "Please specify the imagesize"
	;;
iso*|usb*|raw*)
	_jget mnt ${JAILNAME} mnt
	test -f ${mnt}/boot/kernel/kernel || err 1 "The ${MEDIATYPE} media type requires a jail with a kernel"
	;;
esac

msg "Preparing the image '${IMAGENAME}'"
md=""
CLEANUP_HOOK=cleanup_image
WRKDIR=$(mktemp -d ${POUDRIERE_DATA}/images/${IMAGENAME}-XXXX)
_jget mnt ${JAILNAME} mnt
excludelist=$(mktemp -t excludelist)
mkdir -p ${WRKDIR}/world
mkdir -p ${WRKDIR}/out
[ -z "${EXCLUDELIST}" ] || cat ${EXCLUDELIST} > ${excludelist}
# Some poudriere jail directory used for upgrading source or binary based jail
# are useless on the final image
cat >> ${excludelist} << EOF
usr/src
var/db/freebsd-update
var/db/etcupdate
boot/kernel.old
EOF
case "${MEDIATYPE}" in
usb|*firmware|rawdisk)
	truncate -s ${IMAGESIZE} ${WRKDIR}/raw.img
	md=$(/sbin/mdconfig ${WRKDIR}/raw.img)
	newfs -L ${IMAGENAME} /dev/${md}
	mount /dev/${md} ${WRKDIR}/world
	;;
zrawdisk)
	truncate -s ${IMAGESIZE} ${WRKDIR}/raw.img
	md=$(/sbin/mdconfig ${WRKDIR}/raw.img)
	zroot=${IMAGENAME}root
	zpool create \
		-O mountpoint=none \
		-O compression=lz4 \
		-O atime=off \
		-R ${WRKDIR}/world ${zroot} /dev/${md}
	zfs create -o mountpoint=none ${zroot}/ROOT
	zfs create -o mountpoint=/ ${zroot}/ROOT/default
	zfs create -o mountpoint=/var ${zroot}/var
	zfs create -o mountpoint=/var/tmp -o setuid=off ${zroot}/var/tmp
	zfs create -o mountpoint=/tmp -o setuid=off ${zroot}/tmp
	zfs create -o mountpoint=/home ${zroot}/home
	chmod 1777 ${WRKDIR}/world/tmp ${WRKDIR}/world/var/tmp
	zfs create -o mountpoint=/var/crash \
		-o exec=off -o setuid=off \
		${zroot}/var/crash
	zfs create -o mountpoint=/var/log \
		-o exec=off -o setuid=off \
		${zroot}/var/log
	zfs create -o mountpoint=/var/run \
		-o exec=off -o setuid=off \
		${zroot}/var/run
	zfs create -o mountpoint=/var/db \
		-o exec=off -o setuid=off \
		${zroot}/var/db
	zfs create -o mountpoint=/var/mail \
		-o exec=off -o setuid=off \
		${zroot}/var/mail
	zfs create -o mountpoint=/var/cache \
		-o compression=off \
		-o exec=off -o setuid=off \
		${zroot}/var/cache
	zfs create -o mountpoint=/var/empty ${zroot}/var/empty
	;;
esac

# Use of tar given cpdup has a pretty useless -X option for this case
tar -C ${mnt} -X ${excludelist} -cf - . | tar -xf - -C ${WRKDIR}/world
touch ${WRKDIR}/src.conf
[ ! -f ${POUDRIERED}/src.conf ] || cat ${POUDRIERED}/src.conf > ${WRKDIR}/src.conf
[ ! -f ${POUDRIERED}/${JAILNAME}-src.conf ] || cat ${POUDRIERED}/${JAILNAME}-src.conf >> ${WRKDIR}/src.conf
[ ! -f ${POUDRIERED}/image-${JAILNAME}-src.conf ] || cat ${POUDRIERED}/image-${JAILNAME}-src.conf >> ${WRKDIR}/src.conf
[ ! -f ${POUDRIERED}/image-${JAILNAME}-${SETNAME}-src.conf ] || cat ${POUDRIERED}/image-${JAILNAME}-${SETNAME}-src.conf >> ${WRKDIR}/src.conf
make -C ${mnt}/usr/src DESTDIR=${WRKDIR}/world BATCH_DELETE_OLD_FILES=yes SRCCONF=${WRKDIR}/src.conf delete-old delete-old-libs

mkdir -p ${WRKDIR}/world/etc/rc.conf.d
echo "hostname=${HOSTNAME:-poudriere-image}" > ${WRKDIR}/world/etc/rc.conf.d/hostname
[ ! -d "${EXTRADIR}" ] || cp -fRLp ${EXTRADIR}/ ${WRKDIR}/world/
mv ${WRKDIR}/world/etc/login.conf.orig ${WRKDIR}/world/etc/login.conf
cap_mkdb ${WRKDIR}/world/etc/login.conf

# install packages if any is needed
if [ -n "${PACKAGELIST}" ]; then
	mkdir -p ${WRKDIR}/world/tmp/packages
	mount -t nullfs ${POUDRIERE_DATA}/packages/${MASTERNAME} ${WRKDIR}/world/tmp/packages
	cat > ${WRKDIR}/world/tmp/repo.conf <<-EOF
	FreeBSD: { enabled: false }
	local: { url: file:///tmp/packages }
	EOF
	cat ${PACKAGELIST} | xargs chroot ${WRKDIR}/world env ASSUME_ALWAYS_YES=yes REPOS_DIR=/tmp pkg install
	rm -rf ${WRKDIR}/world/var/cache/pkg
	umount ${WRKDIR}/world/tmp/packages
	rmdir ${WRKDIR}/world/tmp/packages
	rm ${WRKDIR}/world/var/db/pkg/repo-*
fi

case ${MEDIATYPE} in
*mfs)
	cat >> ${WRKDIR}/world/etc/fstab <<-EOF
	/dev/ufs/${IMAGENAME} / ufs rw 0 0
	tmpfs /tmp tmpfs rw,mode=1777 0 0
	EOF
	makefs -B little ${IMAGESIZE:+-s ${IMAGESIZE}} -o label=${IMAGENAME} ${WRKDIR}/out/mfsroot ${WRKDIR}/world
	if which -s pigz; then
		GZCMD=pigz
	fi
	case "${MEDIATYPE}" in
	*zmfs) ${GZCMD:-gzip} -9 ${WRKDIR}/out/mfsroot ;;
	esac
	cpdup -i0 ${WRKDIR}/world/boot ${WRKDIR}/out/boot
	cat >> ${WRKDIR}/out/boot/loader.conf <<-EOF
	tmpfs_load="YES"
	mfs_load="YES"
	mfs_type="mfs_root"
	mfs_name="/mfsroot"
	vfs.root.mountfrom="ufs:/dev/ufs/${IMAGENAME}"
	EOF
	;;
usb|rawdisk)
	cat >> ${WRKDIR}/world/etc/fstab <<-EOF
	/dev/ufs/${IMAGENAME} / ufs rw 1 1
	EOF
	;;
*firmware)
	# Configuring nanobsd-like mode
	# It re-use diskless(8) framework but using a /cfg configuration partition
	# It needs a "config save" script too, like the nanobsd example:
	#  /usr/src/tools/tools/nanobsd/Files/root/save_cfg
	# Or the BSDRP config script:
	#  https://github.com/ocochard/BSDRP/blob/master/BSDRP/Files/usr/local/sbin/config
	# Because rootfs is readonly, it create ramdisks for /etc and /var
	# Then we need to replace /tmp by a symlink to /var/tmp
	# For more information, read /etc/rc.initdiskless
	cat >> ${WRKDIR}/world/etc/fstab <<-EOF
	/dev/gpt/${IMAGENAME}1 / ufs ro 1 1
	/dev/gpt/cfg /cfg ufs rw,noatime,noauto 2 2
	/dev/gpt/data /data ufs rw,noauto,failok 2 2
	EOF
	# Enable diskless(8) mode
	touch ${WRKDIR}/world/etc/diskless
	for d in cfg data; do
		mkdir -p ${WRKDIR}/world/$d
	done
	# Declare system name into /etc/nanobsd.conf: Allow to re-use nanobsd script
	echo "NANO_DRIVE=gpt/${IMAGENAME}" > ${WRKDIR}/world/etc/nanobsd.conf
	# Move /usr/local/etc to /etc/local (Only /etc will be backuped)
    if [ -d ${WRKDIR}/world/usr/local/etc ] ; then
        mkdir -p ${WRKDIR}/world/etc/local
		tar -C ${WRKDIR}/world -X ${excludelist} -cf - usr/local/etc/ | tar -xf - -C ${WRKDIR}/world/etc/local
        rm -rf ${WRKDIR}/world/usr/local/etc
        ln -s /etc/local ${WRKDIR}/world/usr/local/etc
    fi

	# Copy /etc and /var to /conf/base as "reference"
	for d in var etc; do
		mkdir -p ${WRKDIR}/world/conf/base/$d ${WRKDIR}/world/conf/default/$d
		tar -C ${WRKDIR}/world -X ${excludelist} -cf - $d | tar -xf - -C ${WRKDIR}/world/conf/base
	done
	# Set ram disks size
	echo "$CFG_SIZE" > ${WRKDIR}/world/conf/base/etc/md_size
	echo "$CFG_SIZE" > ${WRKDIR}/world/conf/base/var/md_size
    echo "mount -o ro /dev/gpt/cfg" > ${WRKDIR}/world/conf/default/etc/remount
	# replace /tmp by a symlink to /var/tmp
	rm -rf ${WRKDIR}/world/tmp
	ln -s /var/tmp ${WRKDIR}/world/tmp
	# For correct booting it needs ufs formatted /cfg and /data partitions
	TMPFILE=`mktemp -t poudriere-firmware` || exit 1
	makefs -B little -s ${CFG_SIZE} ${WRKDIR}/cfg.img ${TMPFILE}
	makefs -B little -s ${DATA_SIZE} ${WRKDIR}/data.img ${TMPFILE}
	;;
zrawdisk)
	cat >> ${WRKDIR}/world/boot/loader.conf <<-EOF
	vfs.root.mountfrom="zfs:${zroot}/ROOT/default"
	EOF
	;;
esac

case ${MEDIATYPE} in
iso*)
	FINALIMAGE=${IMAGENAME}.iso
	makefs -t cd9660 -o rockridge -o label=${IMAGENAME} \
		-o publisher="poudriere" \
		-o bootimage="i386;${WRKDIR}/out/boot/cdboot" \
		-o no-emul-boot ${OUTPUTDIR}/${FINALIMAGE} ${WRKDIR}/out
	;;
usb+*mfs)
	FINALIMAGE=${IMAGENAME}.img
	makefs -B little ${WRKDIR}/img.part ${WRKDIR}/out
	mkimg -s gpt -b ${mnt}/boot/pmbr \
		-p efi:=${mnt}/boot/boot1.efifat \
		-p freebsd-boot:=${mnt}/boot/gptboot \
		-p freebsd-ufs:=${WRKDIR}/img.part \
		-o ${OUTPUTDIR}/${FINALIMAGE}
	;;
usb)
	FINALIMAGE=${IMAGENAME}.img
	mkimg -s gpt -b ${mnt}/boot/pmbr \
		-p efi:=${mnt}/boot/boot1.efifat \
		-p freebsd-boot:=${mnt}/boot/gptboot \
		-p freebsd-ufs:=${WRKDIR}/raw.img \
		-p freebsd-swap::1M \
		-o ${OUTPUTDIR}/${FINALIMAGE}
	umount ${WRKDIR}/world
	/sbin/mdconfig -d -u ${md#md}
	;;
tar)
	FINALIMAGE=${IMAGENAME}.txz
	tar -f ${OUTDIR}/${FINALIMAGE} -cJ -C ${WRKDIR}/out .
	;;
firmware)
	FINALIMAGE=${IMAGENAME}.img
	umount ${WRKDIR}/world
	/sbin/mdconfig -d -u ${md#md}
	md=
	mkimg -s gpt -b ${mnt}/boot/pmbr \
		-p efi:=${mnt}/boot/boot1.efifat \
		-p freebsd-boot:=${mnt}/boot/gptboot \
		-p freebsd-ufs/${IMAGENAME}1:=${WRKDIR}/raw.img \
		-p freebsd-ufs/${IMAGENAME}2::${IMAGESIZE} \
		-p freebsd-ufs/cfg:=${WRKDIR}/cfg.img \
		-p freebsd-ufs/data:=${WRKDIR}/data.img \
		-o ${OUTPUTDIR}/${FINALIMAGE}
	;;
rawfirmware)
	FINALIMAGE=${IMAGENAME}.raw
	umount ${WRKDIR}/world
	/sbin/mdconfig -d -u ${md#md}
	md=
	mv ${WRKDIR}/raw.img ${OUTPUTDIR}/${FINALIMAGE}
	;;
rawdisk)
	FINALIMAGE=${IMAGENAME}.img
	umount ${WRKDIR}/world
	/sbin/mdconfig -d -u ${md#md}
	md=
	mv ${WRKDIR}/raw.img ${OUTPUTDIR}/${FINALIMAGE}
	;;
zrawdisk)
	FINALIMAGE=${IMAGENAME}.img
	zfs umount -f ${zroot}/ROOT/default
	zfs set mountpoint=none ${zroot}/ROOT/default
	zfs set readonly=on ${zroot}/var/empty
	zpool set bootfs=${zroot}/ROOT/default ${zroot}
	zpool set autoexpand=on ${zroot}
	zpool export ${zroot}
	zroot=
	dd if=${mnt}/boot/zfsboot of=/dev/${md} count=1
	dd if=${mnt}/boot/zfsboot of=/dev/${md} iseek=1 oseek=1024
	/sbin/mdconfig -d -u ${md#md}
	md=
	mv ${WRKDIR}/raw.img ${OUTPUTDIR}/${FINALIMAGE}
	;;
esac

CLEANUP_HOOK=delete_image
msg "Image available at: ${OUTPUTDIR}/${FINALIMAGE}"
