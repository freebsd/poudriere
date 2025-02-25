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

usb_check()
{

	[ -n "${IMAGESIZE}" ] || err 1 "Please specify the imagesize"

	[ -f "${mnt}/boot/kernel/kernel" ] || \
	    err 1 "The ${MEDIATYPE} media type requires a jail with a kernel"
}

usb_prepare()
{
	:
}

usb_build()
{

	if [ "$1" = "mfs" ]; then
		mfs_build
		return 0
	elif [ "$1" = "zmfs" ]; then
		zmfs_build
		return 0
	fi

	msg "Building UFS image for usb"
	cat >> ${WRKDIR}/world/etc/fstab <<-EOF
	/dev/ufs/${IMAGENAME} / ufs rw 1 1
	EOF
	if [ -n "${SWAPSIZE}" -a "${SWAPSIZE}" != "0" ]; then
		cat >> ${WRKDIR}/world/etc/fstab <<-EOSWAP
		/dev/gpt/swapspace none swap sw 0 0
		EOSWAP
	fi
	# Figure out Partition sizes
	OS_SIZE=
	calculate_ospart_size "1" "${NEW_IMAGESIZE_SIZE}" "0" "0" "${SWAPSIZE}"
	# Prune off a bit to fit the extra partitions and loaders
	OS_SIZE=$(( $OS_SIZE - 1 ))
	WORLD_SIZE=$(du -ms ${WRKDIR}/world | awk '{print $1}')
	if [ ${WORLD_SIZE} -gt ${OS_SIZE} ]; then
		err 2 "Installed OS Partition needs: ${WORLD_SIZE}m, but the OS Partitions are only: ${OS_SIZE}m.  Increase -s"
	fi
	makefs -B little ${OS_SIZE:+-s ${OS_SIZE}}m -o label=${IMAGENAME} \
	       -o version=2 ${WRKDIR}/raw.img ${WRKDIR}/world >/dev/null 2>&1
	msg "UFS image for USB built"
}

usb_generate()
{

	FINALIMAGE=${IMAGENAME}.img
	espfilename=$(mktemp /tmp/efiboot.XXXXXX)
	make_esp_file ${espfilename} 10 ${WRKDIR}/world/boot/loader.efi

	if [ "$1" = "mfs" ] || [ "$1" = "zmfs" ]; then
		makefs -B little ${WRKDIR}/img.part ${WRKDIR}/out >/dev/null 2>&1
		ufsimage=${WRKDIR}/img.part
	else
		ufsimage=${WRKDIR}/raw.img
	fi

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
		gptboot="-p freebsd-boot:=${mnt}/boot/gptboot"
	fi
	mkimg -s gpt ${pmbr} \
	      -p efi/efiboot0:=${espfilename} \
	      ${gptboot} \
	      ${SWAPFIRST} \
	      -p freebsd-ufs:=${ufsimage} \
	      ${SWAPLAST} \
	      -o "${OUTPUTDIR}/${FINALIMAGE}"
	rm -rf ${espfilename}
}
