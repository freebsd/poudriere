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
    -n imagename    -- the name of the generated image
    -h hostname     -- the image hostname
    -t type         -- Type of image can be one of (default iso+mfs):
                       iso, usb, usb+mfs, iso+mfs, rawdisk, tar
    -X exclude      -- file containing the list in cpdup format
    -f packagelist  -- list of packages to install
    -c extradir     -- the content of the directory will copied in the target
EOF
	exit 1
}

delete_image() {
	[ ! -f "${excludelist}" ] || rm -f ${excludelist}
	destroyfs ${WRKDIR} image
}

cleanup_image() {
	msg "Error while create image. cleaning up." >&2
	delete_image
}

while getopts "o:j:p:z:n:t:X:f:c:h:" FLAG; do
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
			iso|usb|usb+mfs|iso+mfs|rawdisk|tar) ;;
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
		f)
			[ -f "${OPTARG}" ] || err 1 "No such package list: ${OPTARG}"
			PACKAGELIST=${OPTARG}
			;;
		c)
			[ -d "${OPTARG}" ] || err 1 "No such extract directory: ${OPTARG}"
			EXTRADIR=${OPTARG}
			;;
		*)
			echo "Unknown flag '${FLAG}'"
			usage
			;;
	esac
done

saved_argv="$@"
shift $((OPTIND-1))

. ${SCRIPTPREFIX}/common.sh
: ${MEDIATYPE:=iso+mfs}

[ -n "${JAILNAME}" ] || usage

: ${OUTPUTDIR:=${POUDRIERE_DATA}/images/}
: ${IMAGENAME:=poudriereimage}

# Limitation on isos
case "${IMAGENAME}" in
''|*[!A-Za-z0-9]*)
	err 1 "Name can only contain alphanumeric characters"
	;;
esac

mkdir -p ${OUTPUTDIR}

jail_exists ${JAILNAME} || err 1 "The jail ${JAILNAME} does not exists"
case "${MEDIATYPE}" in
iso*|usb*|raw*)
	_jget mnt ${JAILNAME} mnt
	test -f ${mnt}/boot/kernel/kernel || err 1 "The ${MEDIATYPE} media type requires a jail with a kernel"
	;;
esac

msg "Preparing the image '${IMAGENAME}'"
CLEANUP_HOOK=cleanup_image
WRKDIR=$(mktemp -d ${POUDRIERE_DATA}/images/${IMAGENAME}-XXXX)
_jget mnt ${JAILNAME} mnt
excludelist=$(mktemp -t excludelist)
mkdir -p ${WRKDIR}/world
mkdir -p ${WRKDIR}/out
[ -z "${EXCLUDELIST}" ] || cat ${EXCLUDELIST} > ${excludelist}
cat >> ${excludelist} << EOF
usr/src
EOF
cat ${excludelist}
# Use of tar given cpdup has a pretty useless -X option for this case
tar -C ${mnt} -X ${excludelist} -cf - . | tar -xf - -C ${WRKDIR}/world
mkdir -p ${WRKDIR}/world/etc/rc.conf.d
echo "${HOSTNAME:-poudriere-image}" > ${WRKDIR}/world/etc/rc.conf.d/hostname
[ ! -d "${EXTRADIR}" ] || cpdup -i0 ${EXTRADIR} ${WRKDIR}/world

case ${MEDIATYPE} in
*mfs)
	cat >> ${WRKDIR}/world/etc/fstab <<-EOF
	/dev/ufs/${IMAGENAME} / ufs rw 0 0
	tmpfs /tmp tmpfs rw,mode=1777 0 0
	EOF
	makefs -B little -o label=${IMAGENAME} ${WRKDIR}/out/mfsroot ${WRKDIR}/world
	if which -s pigz; then
		GZCMD=pigz
	fi
	${GZCMD:-gzip} -9 ${WRKDIR}/out/mfsroot
	cpdup -i0 ${WRKDIR}/world/boot ${WRKDIR}/out/boot
	cat >> ${WRKDIR}/out/boot/loader.conf <<-EOF
	geom_uzip_load="YES"
	tmpfs_load="YES"
	mfs_load="YES"
	mfs_type="mfs_root"
	mfs_name="/mfsroot"
	vfs.root.mountfrom="ufs:/dev/ufs/${IMAGENAME}
	EOF
	;;
esac

case ${MEDIATYPE} in
iso*)
	set -x
	makefs -t cd9660 -o rockridge -o label=${IMAGENAME} \
		-o publisher="poudriere" \
		-o bootimage="i386;${WRKDIR}/out/boot/cdboot" \
		-o no-emul-boot ${OUTPUTDIR}/${IMAGENAME}.iso ${WRKDIR}/out
	FINALIMAGE=${IMAGENAME}.iso
	set +x
	;;
esac

msg "Image available at: ${OUTPUTDIR}${FINALIMAGE}"
