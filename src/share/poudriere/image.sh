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
    -c overlaydir   -- The content of the overlay directory will be copied into
                       the image
    -f packagelist  -- List of packages to install
    -h hostname     -- The image hostname
    -j jail         -- Jail
    -m overlaydir   -- Build a miniroot image as well (for tar type images), and
                       overlay this directory into the miniroot image
    -n imagename    -- The name of the generated image
    -o outputdir    -- Image destination directory
    -p portstree    -- Ports tree
    -s size         -- Set the image size
    -t type         -- Type of image can be one of (default iso+zmfs):
                    -- iso, iso+mfs, iso+zmfs, usb, usb+mfs, usb+zmfs,
                       rawdisk, zrawdisk, tar, firmware, rawfirmware,
                       embedded
    -X excludefile  -- File containing the list in cpdup format
    -z set          -- Set
EOF
	exit 1
}

delete_image() {
	[ ! -f "${excludelist}" ] || rm -f ${excludelist}
	[ -z "${zroot}" ] || zpool destroy -f ${zroot}

	destroyfs ${WRKDIR} image
}

cleanup_image() {
	msg "Error while create image. cleaning up." >&2
	delete_image
}

recursecopylib() {
	path=$1
	case $1 in
	*/*) ;;
	lib*)
		if [ -e "${WRKDIR}/world/lib/$1" ]; then
			cp ${WRKDIR}/world/lib/$1 ${mroot}/lib
			path=lib/$1
		elif [ -e "${WRKDIR}/world/usr/lib/$1" ]; then
			cp ${WRKDIR}/world/usr/lib/$1 ${mroot}/usr/lib
			path=usr/lib/$1
		fi
		;;
	esac
	for i in $( (readelf -d ${mroot}/$path 2>/dev/null || :) | awk '$2 == "NEEDED" { gsub(/\[/,"", $NF ); gsub(/\]/,"",$NF) ; print $NF }'); do
		[ -f ${mroot}/lib/$i ] || recursecopylib $i
	done
}

mkminiroot() {
	msg "Making miniroot"
	[ -z "${MINIROOT}" ] && err 1 "MINIROOT not defined"
	mroot=${WRKDIR}/miniroot
	dirs="etc dev boot bin usr/bin libexec lib usr/lib sbin"
	files="sbin/init etc/pwd.db etc/spwd.db"
	files="${files} bin/sh sbin/halt sbin/fasthalt sbin/fastboot sbin/reboot"
	files="${files} usr/bin/bsdtar libexec/ld-elf.so.1 sbin/newfs"
	files="${files} sbin/mdconfig usr/bin/fetch sbin/ifconfig sbin/route sbin/mount"
	files="${files} sbin/umount bin/mkdir bin/kenv usr/bin/sed"

	for d in ${dirs}; do
		mkdir -p ${mroot}/${d}
	done

	for f in ${files}; do
		cp -p ${WRKDIR}/world/${f} ${mroot}/${f}
		recursecopylib ${f}
	done
	cp -fRLp ${MINIROOT}/ ${mroot}/

	makefs ${OUTPUTDIR}/${IMAGENAME}-miniroot ${mroot}
	[ -f ${OUTPUTDIR}/${IMAGENAME}-miniroot.gz ] && rm ${OUTPUTDIR}/${IMAGENAME}-miniroot.gz
	gzip -9 ${OUTPUTDIR}/${IMAGENAME}-miniroot
}

. ${SCRIPTPREFIX}/common.sh
HOSTNAME=poudriere-image

while getopts "c:f:h:j:m:n:o:p:s:t:X:z:" FLAG; do
	case "${FLAG}" in
		c)
			[ -d "${OPTARG}" ] || err 1 "No such extract directory: ${OPTARG}"
			EXTRADIR=$(realpath ${OPTARG})
			;;
		f)
			# If this is a relative path, add in ${PWD} as
			# a cd / was done.
			[ "${OPTARG#/}" = "${OPTARG}" ] && \
			    OPTARG="${SAVED_PWD}/${OPTARG}"
			[ -f "${OPTARG}" ] || err 1 "No such package list: ${OPTARG}"
			PACKAGELIST=${OPTARG}
			;;
		h)
			HOSTNAME=${OPTARG}
			;;
		j)
			JAILNAME=${OPTARG}
			;;
		m)
			[ -d "${OPTARG}" ] || err 1 "No such miniroot overlay directory: ${OPTARG}"
			MINIROOT=$(realpath ${OPTARG})
			;;
		n)
			IMAGENAME=${OPTARG}
			;;
		o)
			# If this is a relative path, add in ${PWD} as
			# a cd / was done.
			[ "${OPTARG#/}" = "${OPTARG}" ] && \
			    OPTARG="${SAVED_PWD}/${OPTARG}"
			OUTPUTDIR=${OPTARG}
			;;
		p)
			PTNAME=${OPTARG}
			;;
		s)
			IMAGESIZE="${OPTARG}"
			;;
		t)
			MEDIATYPE=${OPTARG}
			case ${MEDIATYPE} in
			iso|iso+mfs|iso+zmfs|usb|usb+mfs|usb+zmfs) ;;
			rawdisk|zrawdisk|tar|firmware|rawfirmware) ;;
			embedded) ;;
			*) err 1 "invalid mediatype: ${MEDIATYPE}"
			esac
			;;
		X)
			[ -f "${OPTARG}" ] || err 1 "No such exclude list ${OPTARG}"
			EXCLUDELIST=$(realpath ${OPTARG})
			;;
		z)
			[ -n "${OPTARG}" ] || err 1 "Empty set name"
			SETNAME="${OPTARG}"
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

: ${MEDIATYPE:=none}
: ${PTNAME:=default}

[ -n "${JAILNAME}" ] || usage

: ${OUTPUTDIR:=${POUDRIERE_DATA}/images/}
: ${IMAGENAME:=poudriereimage}
MASTERNAME=${JAILNAME}-${PTNAME}${SETNAME:+-${SETNAME}}

# CFG_SIZE set /etc and /var ramdisk size and /cfg partition size
# DATA_SIZE set /data partition size
CFG_SIZE='32m'
DATA_SIZE='32m'

case "${MEDIATYPE}" in
*iso*)
	# Limitation on isos
	case "${IMAGENAME}" in
	''|*[!A-Za-z0-9]*)
		err 1 "Name can only contain alphanumeric characters"
		;;
	esac
	;;
none)
	err 1 "Missing -t option"
	;;
esac

mkdir -p ${OUTPUTDIR}

jail_exists ${JAILNAME} || err 1 "The jail ${JAILNAME} does not exist"
_jget arch ${JAILNAME} arch
get_host_arch host_arch
case "${MEDIATYPE}" in
usb|*firmware|rawdisk|embedded)
	[ -n "${IMAGESIZE}" ] || err 1 "Please specify the imagesize"
	_jget mnt ${JAILNAME} mnt
	test -f ${mnt}/boot/kernel/kernel || err 1 "The ${MEDIATYPE} media type requires a jail with a kernel"
	;;
iso*|usb*|raw*)
	_jget mnt ${JAILNAME} mnt
	test -f ${mnt}/boot/kernel/kernel || err 1 "The ${MEDIATYPE} media type requires a jail with a kernel"
	;;
esac

msg "Preparing the image '${IMAGENAME}'"
md=""
CLEANUP_HOOK=cleanup_image
test -d ${POUDRIERE_DATA}/images || mkdir ${POUDRIERE_DATA}/images
WRKDIR=$(mktemp -d ${POUDRIERE_DATA}/images/${IMAGENAME}-XXXX)
_jget mnt ${JAILNAME} mnt
excludelist=$(mktemp -t excludelist)
mkdir -p ${WRKDIR}/world
mkdir -p ${WRKDIR}/out
[ -z "${EXCLUDELIST}" ] || cat ${EXCLUDELIST} > ${excludelist}
cat >> ${excludelist} << EOF
usr/src
var/db/freebsd-update
var/db/etcupdate
boot/kernel.old
EOF
case "${MEDIATYPE}" in
embedded)
	truncate -s ${IMAGESIZE} ${WRKDIR}/raw.img
	md=$(/sbin/mdconfig ${WRKDIR}/raw.img)
	gpart create -s mbr ${md}
	gpart add -t '!6' -a 63 -s 20m ${md}
	gpart set -a active -i 1 ${md}
	newfs_msdos -F16 -L msdosboot /dev/${md}s1
	gpart add -t freebsd ${md}
	gpart create -s bsd ${md}s2
	gpart add -t freebsd-ufs -a 64k ${md}s2
	newfs -U -L ${IMAGENAME} /dev/${md}s2a
	mount /dev/${md}s2a ${WRKDIR}/world
	mkdir -p ${WRKDIR}/world/boot/msdos
	mount_msdosfs /dev/${md}s1 /${WRKDIR}/world/boot/msdos
	;;
rawdisk)
	truncate -s ${IMAGESIZE} ${WRKDIR}/raw.img
	md=$(/sbin/mdconfig ${WRKDIR}/raw.img)
	newfs -j -L ${IMAGENAME} /dev/${md}
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

# Set hostname
if [ -n "${HOSTNAME}" ]; then
	mkdir -p ${WRKDIR}/world/etc/rc.conf.d
	echo "hostname=${HOSTNAME}" > ${WRKDIR}/world/etc/rc.conf.d/hostname
fi

[ ! -d "${EXTRADIR}" ] || cp -fRLp ${EXTRADIR}/ ${WRKDIR}/world/
mv ${WRKDIR}/world/etc/login.conf.orig ${WRKDIR}/world/etc/login.conf
cap_mkdb ${WRKDIR}/world/etc/login.conf

# install packages if any is needed
if [ -n "${PACKAGELIST}" ]; then
	mkdir -p ${WRKDIR}/world/tmp/packages
	${NULLMOUNT} ${POUDRIERE_DATA}/packages/${MASTERNAME} ${WRKDIR}/world/tmp/packages
	if [ "${arch}" == "${host_arch}" ]; then
		cat > ${WRKDIR}/world/tmp/repo.conf <<-EOF
	FreeBSD: { enabled: false }
	local: { url: file:///tmp/packages }
	EOF
		cat ${PACKAGELIST} | xargs chroot ${WRKDIR}/world env ASSUME_ALWAYS_YES=yes REPOS_DIR=/tmp pkg install
	else
		cat > ${WRKDIR}/world/tmp/repo.conf <<-EOF
	FreeBSD: { enabled: false }
	local: { url: file:///${WRKDIR}/world/tmp/packages }
	EOF
		env ASSUME_ALWAYS_YES=yes SYSLOG=no REPOS_DIR=/${WRKDIR}/world/tmp/ ABI_FILE=/${WRKDIR}/world/usr/lib/crt1.o pkg -r ${WRKDIR}/world/ install pkg
		cat ${PACKAGELIST} | xargs env ASSUME_ALWAYS_YES=yes SYSLOG=no REPOS_DIR=/${WRKDIR}/world/tmp/ ABI_FILE=/${WRKDIR}/world/usr/lib/crt1.o pkg -r ${WRKDIR}/world/ install
	fi
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
	if command -v pigz >/dev/null; then
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
iso)
	imageupper=$(echo ${IMAGENAME} | tr '[:lower:]' '[:upper:]')
	cat >> ${WRKDIR}/world/etc/fstab <<-EOF
	/dev/iso9660/${imageupper} / cd9660 ro 0 0
	tmpfs /tmp tmpfs rw,mode=1777 0 0
	EOF
	cpdup -i0 ${WRKDIR}/world/boot ${WRKDIR}/out/boot
	;;
rawdisk)
	cat >> ${WRKDIR}/world/etc/fstab <<-EOF
	/dev/ufs/${IMAGENAME} / ufs rw 1 1
	EOF
	;;
embedded)
	if [ -f ${WRKDIR}/world/boot/ubldr.bin ]; then
	    cp ${WRKDIR}/world/boot/ubldr.bin ${WRKDIR}/world/boot/msdos/
	fi
	cat >> ${WRKDIR}/world/etc/fstab <<-EOF
	/dev/ufs/${IMAGENAME} / ufs rw 1 1
	/dev/msdosfs/MSDOSBOOT /boot/msdos msdosfs rw,noatime 0 0
	EOF
	;;
usb)
	cat >> ${WRKDIR}/world/etc/fstab <<-EOF
	/dev/ufs/${IMAGENAME} / ufs rw 1 1
	EOF
	makefs -B little ${IMAGESIZE:+-s ${IMAGESIZE}} -o label=${IMAGENAME} \
		-o version=2 ${WRKDIR}/raw.img ${WRKDIR}/world
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
	echo "/dev/gpt/${IMAGENAME}1 / ufs ro 1 1" >> ${WRKDIR}/world/etc/fstab
	echo '/dev/gpt/cfg  /cfg  ufs rw,noatime,noauto        2 2' >> ${WRKDIR}/world/etc/fstab
	echo '/dev/gpt/data /data ufs rw,noatime,noauto,failok 2 2' >> ${WRKDIR}/world/etc/fstab
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

	# Copy save_cfg to /etc
	cp ${mnt}/usr/src/tools/tools/nanobsd/Files/root/save_cfg ${WRKDIR}/world/etc/

	# Figure out Partition sizes
	OS_SIZE=
	calculate_ospart_size ${IMAGESIZE} ${CFG_SIZE} ${DATA_SIZE}
	# Prune off a bit to fit the extra partitions and loaders
	OS_SIZE=$(( ${OS_SIZE} - 1 ))
	WORLD_SIZE=$(du -ms ${WRKDIR}/world | awk '{print $1}')
	if [ ${WORLD_SIZE} -gt ${OS_SIZE} ]; then
		err 2 "Installed OS Partition needs: ${WORLD_SIZE}m, but the OS Partitions are only: ${OS_SIZE}m.  Increase -s"
	fi

	# For correct booting it needs ufs formatted /cfg and /data partitions
	TMPDIR=`mktemp -d -t poudriere-firmware` || exit 1
	# Set proper permissions to this empty directory: /cfg (so /etc) and /data once mounted will inherit them
	chmod -R 755 ${TMPDIR}
	makefs -B little -s ${CFG_SIZE} ${WRKDIR}/cfg.img ${TMPDIR}
	makefs -B little -s ${DATA_SIZE} ${WRKDIR}/data.img ${TMPDIR}
	rm -rf ${TMPDIR}
	makefs -B little -s ${OS_SIZE}m -o label=${IMAGENAME} \
		-o version=2 ${WRKDIR}/raw.img ${WRKDIR}/world
	;;
zrawdisk)
	cat >> ${WRKDIR}/world/boot/loader.conf <<-EOF
	vfs.root.mountfrom="zfs:${zroot}/ROOT/default"
	EOF
	;;
tar)
	if [ -n "${MINIROOT}" ]; then
		mkminiroot
	fi
	;;
esac

case ${MEDIATYPE} in
iso)
	FINALIMAGE=${IMAGENAME}.iso
	makefs -t cd9660 -o rockridge -o label=${IMAGENAME} \
		-o publisher="poudriere" \
		-o bootimage="i386;${WRKDIR}/out/boot/cdboot" \
		-o no-emul-boot ${OUTPUTDIR}/${FINALIMAGE} ${WRKDIR}/world
	;;
iso+*mfs)
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
	;;
tar)
	FINALIMAGE=${IMAGENAME}.txz
	tar -f - -c -C ${WRKDIR}/world . | xz -T0 -c > ${OUTPUTDIR}/${FINALIMAGE}
	;;
firmware)
	FINALIMAGE=${IMAGENAME}.img
	mkimg -s gpt -C ${IMAGESIZE} -b ${mnt}/boot/pmbr \
		-p efi:=${mnt}/boot/boot1.efifat \
		-p freebsd-boot:=${mnt}/boot/gptboot \
		-p freebsd-ufs/${IMAGENAME}1:=${WRKDIR}/raw.img \
		-p freebsd-ufs/${IMAGENAME}2:=${WRKDIR}/raw.img \
		-p freebsd-ufs/cfg:=${WRKDIR}/cfg.img \
		-p freebsd-ufs/data:=${WRKDIR}/data.img \
		-o ${OUTPUTDIR}/${FINALIMAGE}
	;;
rawfirmware)
	FINALIMAGE=${IMAGENAME}.raw
	mv ${WRKDIR}/raw.img ${OUTPUTDIR}/${FINALIMAGE}
	;;
rawdisk)
	FINALIMAGE=${IMAGENAME}.img
	umount ${WRKDIR}/world
	/sbin/mdconfig -d -u ${md#md}
	md=
	mv ${WRKDIR}/raw.img ${OUTPUTDIR}/${FINALIMAGE}
	;;
embedded)
	FINALIMAGE=${IMAGENAME}.img
	umount ${WRKDIR}/world/boot/msdos
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
