#!/bin/sh

#
# Copyright (c) 2022 Christer Edwards <christer.edwards@gmail.com>
# Copyright (c) 2021 Emmanuel Vadot <manu@FreeBSD.org>
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

hybridiso_check()
{

	# Limitation on isos
	case "${IMAGENAME}" in
	''|*[!A-Za-z0-9]*)
		err 1 "Name can only contain alphanumeric characters"
		;;
	esac

	[ -f "${mnt}/boot/kernel/kernel" ] || \
	    err 1 "The ${MEDIATYPE} media type requires a jail with a kernel"
}

hybridiso_prepare()
{
	:
}

hybridiso_build()
{

	imageupper=$(echo ${IMAGENAME} | tr '[:lower:]' '[:upper:]')
	cat >> ${WRKDIR}/world/etc/fstab <<-EOF
	/dev/iso9660/${imageupper} / cd9660 ro 0 0
	tmpfs /tmp tmpfs rw,mode=1777 0 0
	EOF
	do_clone -r ${WRKDIR:?}/world/boot ${WRKDIR:?}/out/boot
}

hybridiso_generate()
{
	local entry entries

	FINALIMAGE=${IMAGENAME}.iso
	espfilename=$(mktemp /tmp/efiboot.XXXXXX)
	make_esp_file ${espfilename} 10 ${WRKDIR}/world/boot/loader.efi

	# Make ISO image.
	makefs -t cd9660 -o rockridge -o label=${IMAGENAME} \
	       -o publisher="poudriere" \
	       -o bootimage="i386;${WRKDIR}/out/boot/cdboot" \
	       -o bootimage="i386;${espfilename}" \
	       -o platformid=efi \
	       -o no-emul-boot "${OUTPUTDIR}/${FINALIMAGE}" ${WRKDIR}/world

	# Find the EFI System Partition on the ISO.
	entries="$(etdump --format shell ${OUTPUTDIR}/${FINALIMAGE})"
	for entry in ${entries}; do
		eval $entry
		if [ "$et_platform" = "efi" ]; then
			espstart=$(expr $et_lba \* 2048)
			espsize=$(expr $et_sectors \* 512)
			espparam="-p efi/efiboot0::$espsize:$espstart"
			break
		fi
	done

	# Create a GPT image with the partitions needed for hybrid boot.
	imgsize=$(stat -f %z "${OUTPUTDIR}/${FINALIMAGE}")
	mkimg -s gpt \
	    --capacity $imgsize \
	    -b "$WRKDIR/out/boot/pmbr" \
	    -p freebsd-boot:="$WRKDIR/out/boot/isoboot" \
	    $espparam \
	    -o "${OUTPUTDIR}/hybridiso.img"

	# Drop the PMBR, GPT, and boot code into the System Area of the ISO.
	dd if="${OUTPUTDIR}/hybridiso.img" of="${OUTPUTDIR}/${FINALIMAGE}" bs=32k count=1 conv=notrunc
	rm -f "${OUTPUTDIR}/hybridiso.img"
}
