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


# CFG_SIZE set /etc and /var ramdisk size and /cfg partition size
# DATA_SIZE set /data partition size
CFG_SIZE='32m'
DATA_SIZE='32m'

# ESP_SIZE set the EFI system partition size in MB
ESP_SIZE=10

firmware_check()
{

	[ -n "${IMAGESIZE}" ] || err 1 "Please specify the imagesize"
}

firmware_prepare()
{
	:
}

firmware_build()
{

	# Configuring nanobsd-like mode
	# It re-use diskless(8) framework but using a /cfg configuration partition
	# It needs a "config save" script too, like the nanobsd example:
	#  /usr/src/tools/tools/nanobsd/Files/root/save_cfg
	# Or the BSDRP config script:
	#  https://github.com/ocochard/BSDRP/blob/master/BSDRP/Files/usr/local/sbin/config
	# Because rootfs is readonly, it create ramdisks for /etc and /var
	# Then we need to replace /tmp by a symlink to /var/tmp
	# For more information, read /etc/rc.initdiskless
	{
		echo "/dev/gpt/${IMAGENAME}1 / ufs ro 1 1"
		echo '/dev/gpt/cfg  /cfg  ufs rw,noatime,noauto        2 2'
		echo '/dev/gpt/data /data ufs rw,noatime,noauto,failok 2 2'
		if [ -n "${SWAPSIZE}" -a "${SWAPSIZE}" != "0" ]; then
			echo '/dev/gpt/swapspace none swap sw 0 0'
		fi
	} >> "${WRKDIR}/world/etc/fstab"

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
		tar -C ${WRKDIR}/world -X ${excludelist} -cf - usr/local/etc/ | \
		    tar -xf - -C ${WRKDIR}/world/etc/local --strip-components=3
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
	install ${mnt}/usr/src/tools/tools/nanobsd/Files/root/save_cfg ${WRKDIR}/world/conf/base/etc/

	# Figure out Partition sizes
	OS_SIZE=
	calculate_ospart_size "2" "${NEW_IMAGESIZE_SIZE}" "${CFG_SIZE}" "${DATA_SIZE}" "${SWAPSIZE}"
	# Prune off a bit to fit the extra partitions and loaders
	OS_SIZE=$(( OS_SIZE - 1 - ESP_SIZE / 2 ))
	WORLD_SIZE=$(du -ms ${WRKDIR}/world | awk '{print $1}')
	if [ ${WORLD_SIZE} -gt ${OS_SIZE} ]; then
		err 2 "Installed OS Partition needs: ${WORLD_SIZE}m, but the OS Partitions are only: ${OS_SIZE}m.  Increase -s"
	fi

	# For correct booting it needs ufs formatted /cfg and /data partitions
	FTMPDIR=`mktemp -d -t poudriere-firmware` || exit 1
	# Set proper permissions to this empty directory: /cfg (so /etc) and /data once mounted will inherit them
	chmod -R 755 ${FTMPDIR}
	makefs -B little -s ${CFG_SIZE} -o optimization=space,minfree=0,label=cfg ${WRKDIR}/cfg.img ${FTMPDIR}
	makefs -B little -s ${DATA_SIZE} -o label=data ${WRKDIR}/data.img ${FTMPDIR}
	rm -rf ${FTMPDIR}
	makefs -B little -s ${OS_SIZE}m -o optimization=space,minfree=0,label=${IMAGENAME} \
		-o version=2 ${WRKDIR}/raw.img ${WRKDIR}/world
}

firmware_generate()
{

	FINALIMAGE=${IMAGENAME}.img
	if [ ${SWAPSIZE} != "0" ]; then
		SWAPCMD="-p freebsd-swap/swapspace::${SWAPSIZE}"
		if [ $SWAPBEFORE -eq 1 ]; then
			SWAPFIRST="$SWAPCMD"
		else
			SWAPLAST="$SWAPCMD"
		fi
	fi
	espfilename=$(mktemp /tmp/efiboot.XXXXXX)
	make_esp_file ${espfilename} ${ESP_SIZE} ${WRKDIR}/world/boot/gptboot.efi
	mkimg -s gpt -C ${IMAGESIZE} -b ${mnt}/boot/pmbr \
		-p efi/efiboot0:=${espfilename} \
		-p freebsd-boot:=${mnt}/boot/gptboot \
		-p freebsd-ufs/${IMAGENAME}1:=${WRKDIR}/raw.img \
		-p freebsd-ufs/${IMAGENAME}2:=${WRKDIR}/raw.img \
		-p freebsd-ufs/cfg:=${WRKDIR}/cfg.img \
		${SWAPFIRST} \
		-p freebsd-ufs/data:=${WRKDIR}/data.img \
		${SWAPLAST} \
		-o "${OUTPUTDIR}/${FINALIMAGE}"
	rm -rf ${espfilename}
	mv ${WRKDIR}/raw.img "${OUTPUTDIR}/${IMAGENAME}"-upgrade.img
}

rawfirmware_check()
{

	[ -n "${IMAGESIZE}" ] || err 1 "Please specify the imagesize"
}

rawfirmware_prepare()
{
	:
}

rawfirmware_build()
{

	# Configuring nanobsd-like mode
	# It re-use diskless(8) framework but using a /cfg configuration partition
	# It needs a "config save" script too, like the nanobsd example:
	#  /usr/src/tools/tools/nanobsd/Files/root/save_cfg
	# Or the BSDRP config script:
	#  https://github.com/ocochard/BSDRP/blob/master/BSDRP/Files/usr/local/sbin/config
	# Because rootfs is readonly, it create ramdisks for /etc and /var
	# Then we need to replace /tmp by a symlink to /var/tmp
	# For more information, read /etc/rc.initdiskless
	{
		echo "/dev/gpt/${IMAGENAME}1 / ufs ro 1 1"
		echo '/dev/gpt/cfg  /cfg  ufs rw,noatime,noauto        2 2'
		echo '/dev/gpt/data /data ufs rw,noatime,noauto,failok 2 2'
		if [ -n "${SWAPSIZE}" -a "${SWAPSIZE}" != "0" ]; then
			echo '/dev/gpt/swapspace none swap sw 0 0'
		fi
	} >> "${WRKDIR}/world/etc/fstab"

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
		tar -C ${WRKDIR}/world -X ${excludelist} -cf - usr/local/etc/ | \
		    tar -xf - -C ${WRKDIR}/world/etc/local --strip-components=3
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
	install ${mnt}/usr/src/tools/tools/nanobsd/Files/root/save_cfg ${WRKDIR}/world/conf/base/etc/

	# Figure out Partition sizes
	OS_SIZE=
	calculate_ospart_size "2" "${NEW_IMAGESIZE_SIZE}" "${CFG_SIZE}" "${DATA_SIZE}" "${SWAPSIZE}"
	# Prune off a bit to fit the extra partitions and loaders
	OS_SIZE=$(( OS_SIZE - 1 - ESP_SIZE / 2 ))
	WORLD_SIZE=$(du -ms ${WRKDIR}/world | awk '{print $1}')
	if [ ${WORLD_SIZE} -gt ${OS_SIZE} ]; then
		err 2 "Installed OS Partition needs: ${WORLD_SIZE}m, but the OS Partitions are only: ${OS_SIZE}m.  Increase -s"
	fi

	# For correct booting it needs ufs formatted /cfg and /data partitions
	FTMPDIR=`mktemp -d -t poudriere-firmware` || exit 1
	# Set proper permissions to this empty directory: /cfg (so /etc) and /data once mounted will inherit them
	chmod -R 755 ${FTMPDIR}
	makefs -B little -s ${CFG_SIZE} -o optimization=space,minfree=0,label=cfg ${WRKDIR}/cfg.img ${FTMPDIR}
	makefs -B little -s ${DATA_SIZE} -o label=data ${WRKDIR}/data.img ${FTMPDIR}
	rm -rf ${FTMPDIR}
	makefs -B little -s ${OS_SIZE}m -o optimization=space,minfree=0,label=${IMAGENAME} \
		-o version=2 ${WRKDIR}/raw.img ${WRKDIR}/world
}

rawfirmware_generate()
{

	FINALIMAGE=${IMAGENAME}.raw
	mv ${WRKDIR}/raw.img "${OUTPUTDIR}/${FINALIMAGE}"
}
