#!/bin/sh
#
# Copyright (c) 2015 Baptiste Daroussin <bapt@FreeBSD.org>
# All rights reserved.
# Copyright (c) 2020 Allan Jude <allanjude@FreeBSD.org>
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

. ${SCRIPTPREFIX}/common.sh
. ${SCRIPTPREFIX}/image_dump.sh
. ${SCRIPTPREFIX}/image_firmware.sh
. ${SCRIPTPREFIX}/image_hybridiso.sh
. ${SCRIPTPREFIX}/image_iso.sh
. ${SCRIPTPREFIX}/image_mfs.sh
. ${SCRIPTPREFIX}/image_rawdisk.sh
. ${SCRIPTPREFIX}/image_tar.sh
. ${SCRIPTPREFIX}/image_usb.sh
. ${SCRIPTPREFIX}/image_zfs.sh
. ${SCRIPTPREFIX}/image_zsnapshot.sh

usage() {
	[ $# -gt 0 ] && echo "Missing: $*" >&2
	cat << EOF
poudriere image [parameters] [options]

Parameters:
    -j jail         -- Jail
    -t type         -- Type of image can be one of
                    -- hybridiso, iso, iso+mfs, iso+zmfs, usb, usb+mfs, usb+zmfs,
                       rawdisk, zrawdisk, tar, firmware, rawfirmware,
                       dump, zfs+[raw|gpt|send[+full[+be]]], zsnapshot

Options:
    -A post-script  -- Source this script after populating the \$WRKDIR/world
                       directory to apply customizations before exporting the
                       final image.
    -b              -- Place the swap partition before the primary partition(s)
    -B pre-script   -- Source this script instead of using the defaults to setup
                       the disk image and mount it to \$WRKDIR/world before
                       installing the contents to the image
    -c overlaydir   -- The content of the overlay directory will be copied into
                       the image. Owners and permissions will be overwritten if
                       an <overlaydir>.mtree file is found
    -f packagelist  -- List of packages to install
    -h hostname     -- The image hostname
    -i originimage  -- Origin image name
    -m overlaydir   -- Build a miniroot image as well (for tar type images), and
                       overlay this directory into the miniroot image
    -n imagename    -- The name of the generated image
    -o outputdir    -- Image destination directory
    -p portstree    -- Ports tree
    -P pkgbase      -- List of pkgbase packages to install
    -R flags        -- ZFS Replication Flags
    -s size         -- Set the image size
    -S snapshotname -- Snapshot name
    -w size         -- Set the size of the swap partition
    -X excludefile  -- File containing the list in cpdup format
    -z set          -- Set
EOF
	exit ${EX_USAGE}
}

delete_image() {
	[ ! -f "${excludelist}" ] || rm -f ${excludelist}
	[ -z "${zroot}" ] || zpool destroy -f ${zroot:?}
	[ -z "${md}" ] || /sbin/mdconfig -d -u ${md#md}
	[ -z "${zfs_zsnapshot}" ] || zfs destroy -r ${zfs_zsnapshot:?}

	destroyfs ${WRKDIR:?} image || :
}

cleanup_image() {
	msg "Error while create image. cleaning up." >&2
	delete_image
}

recursecopylib() {
	local path libs i

	path=$1
	case $1 in
	*/*) ;;
	lib*)
		if [ -e "${WRKDIR}/world/lib/$1" ]; then
			cp ${WRKDIR}/world/lib/$1 ${mroot:?}/lib
			path=lib/$1
		elif [ -e "${WRKDIR}/world/usr/lib/$1" ]; then
			cp ${WRKDIR}/world/usr/lib/$1 ${mroot:?}/usr/lib
			path=usr/lib/$1
		fi
		;;
	esac
	libs="$( (readelf -d "${mroot:?}/${path}" 2>/dev/null || :) | awk '$2 == "NEEDED" { gsub(/\[/,"", $NF ); gsub(/\]/,"",$NF) ; print $NF }')"
	for i in ${libs}; do
		[ -f ${mroot}/lib/$i ] || recursecopylib $i
	done
}

mkminiroot() {
	msg "Making miniroot"
	[ -z "${MINIROOT}" ] && err 1 "MINIROOT not defined"
	mroot=${WRKDIR:?}/miniroot
	dirs="etc dev boot bin usr/bin libexec lib usr/lib sbin"
	files="bin/kenv"
	files="${files} bin/ls"
	files="${files} bin/mkdir"
	files="${files} bin/sh"
	files="${files} bin/sleep"
	files="${files} etc/pwd.db"
	files="${files} etc/spwd.db"
	files="${files} libexec/ld-elf.so.1"
	files="${files} sbin/fasthalt"
	files="${files} sbin/fastboot"
	files="${files} sbin/halt"
	files="${files} sbin/ifconfig"
	files="${files} sbin/init"
	files="${files} sbin/mdconfig"
	files="${files} sbin/mount"
	files="${files} sbin/newfs"
	files="${files} sbin/ping"
	files="${files} sbin/reboot"
	files="${files} sbin/route"
	files="${files} sbin/umount"
	files="${files} usr/bin/bsdtar"
	files="${files} usr/bin/fetch"
	files="${files} usr/bin/sed"

	for d in ${dirs}; do
		mkdir -p ${mroot:?}/${d}
	done

	for f in ${files}; do
		cp -p ${WRKDIR}/world/${f} ${mroot:?}/${f}
		recursecopylib ${f}
	done
	cp -fRPp ${MINIROOT}/ ${mroot:?}/

	makefs "${OUTPUTDIR:?}/${IMAGENAME}-miniroot" ${mroot}
	[ -f "${OUTPUTDIR:?}/${IMAGENAME}-miniroot.gz" ] && rm "${OUTPUTDIR:?}/${IMAGENAME}-miniroot.gz"
	gzip -9 "${OUTPUTDIR:?}/${IMAGENAME}-miniroot"
}

get_pkg_abi() {
	case ${arch} in
		amd64) echo amd64 ;;
		arm64.aarch64) echo aarch64 ;;
		i386) echo i386 ;;
		arm.armv7) echo armv7 ;;
	esac
}

get_uefi_bootname() {

    case ${arch} in
        amd64) echo bootx64 ;;
        arm64.aarch64) echo bootaa64 ;;
        i386) echo bootia32 ;;
        arm.armv7) echo bootarm ;;
        *) echo boot ;;
    esac
}

make_esp_file() {
    local file size loader device stagedir fatbits efibootname

    msg "Creating ESP image"
    file=$1
    size=$2
    loader=$3
    fat32min=33
    fat16min=2

    if [ "$size" -ge "$fat32min" ]; then
        fatbits=32
    elif [ "$size" -ge "$fat16min" ]; then
        fatbits=16
    else
        fatbits=12
    fi

    stagedir=$(mktemp -d /tmp/stand-test.XXXXXX)
    mkdir -p "${stagedir:?}/EFI/BOOT"
    efibootname=$(get_uefi_bootname)
    cp "${loader}" "${stagedir:?}/EFI/BOOT/${efibootname}.efi"
    makefs -t msdos \
	-o fat_type=${fatbits} \
	-o sectors_per_cluster=1 \
	-o volume_label=EFISYS \
	-s ${size}m \
	"${file}" "${stagedir}" \
	>/dev/null 2>&1
    rm -rf "${stagedir:?}"
    msg "ESP Image created"
}

# Convert @flavor from package list to a unique entry of pkgname, otherwise it
# spits out origin if no flavor.
convert_package_list() {
	local PACKAGELIST="$1"
	local PKG_DBDIR REPOS_DIR ABI_FILE

	PKG_DBDIR=$(mktemp -dt poudriere_pkgdb)
	REPOS_DIR=$(mktemp -dt poudriere_repo)
	# This pkg rquery is always ran in host so we need a host-centric
	# repo.conf always.
	cat > "${REPOS_DIR:?}/repo.conf" <<-EOF
	FreeBSD: { enabled: false }
	local: { url: file:///${WRKDIR}/world/tmp/packages }
	EOF

	export REPOS_DIR PKG_DBDIR
	# Always need this from host.
	export ABI_FILE="${WRKDIR}/world/usr/lib/crt1.o"
	pkg -o ASSUME_ALWAYS_YES=yes update  >/dev/null || :
	pkg rquery '%At %o@%Av %n-%v' | \
	    awk -v pkglist="${PACKAGELIST}" \
	    -f "${AWKPREFIX}/unique_pkgnames_from_flavored_origins.awk"
	rm -rf "${PKG_DBDIR:?}" "${REPOS_DIR:?}"
}

install_world_from_pkgbase()
{
	OSVERSION=$(awk -F '"' '/REVISION=/ { print $2 }' ${mnt}/usr/src/sys/conf/newvers.sh | cut -d '.' -f 1)
	mkdir -p ${WRKDIR:?}/world/etc/pkg/
	pkg_abi=$(get_pkg_abi)
	cat << -EOF > ${WRKDIR:?}/world/etc/pkg/FreeBSD-base.conf
	local: {
               url: file://${POUDRIERE_DATA}/images/${JAILNAME}-repo/FreeBSD:${OSVERSION}:${pkg_abi}/latest,
               enabled: true
	       }
-EOF
	pkg -o ABI_FILE="${mnt}/usr/lib/crt1.o" -o REPOS_DIR=${WRKDIR}/world/etc/pkg/ -o ASSUME_ALWAYS_YES=yes -r ${WRKDIR:?}/world update ${PKG_QUIET}
	msg "Installing base packages"
	while read line; do
		pkg -o ABI_FILE="${mnt}/usr/lib/crt1.o" -o REPOS_DIR=${WRKDIR}/world/etc/pkg/ -o ASSUME_ALWAYS_YES=yes -r ${WRKDIR:?}/world install -r local ${PKG_QUIET} -y ${line}
	done < ${PKGBASELIST}
	rm ${WRKDIR:?}/world/etc/pkg/FreeBSD-base.conf
	msg "Base packages installed"
}

install_world()
{
    # Use of tar given cpdup has a pretty useless -X option for this case
	msg "Installing world with tar"
	tar -C ${mnt:?} -X ${excludelist} -cf - . | tar -xf - -C ${WRKDIR:?}/world
	touch ${WRKDIR:?}/src.conf
	[ ! -f ${POUDRIERED}/src.conf ] || cat ${POUDRIERED}/src.conf > ${WRKDIR:?}/src.conf
	[ ! -f ${POUDRIERED}/${JAILNAME}-src.conf ] || cat ${POUDRIERED}/${JAILNAME}-src.conf >> ${WRKDIR:?}/src.conf
	[ ! -f ${POUDRIERED}/image-${JAILNAME}-src.conf ] || cat ${POUDRIERED}/image-${JAILNAME}-src.conf >> ${WRKDIR:?}/src.conf
	[ ! -f ${POUDRIERED}/image-${JAILNAME}-${SETNAME}-src.conf ] || cat ${POUDRIERED}/image-${JAILNAME}-${SETNAME}-src.conf >> ${WRKDIR:?}/src.conf
	make -s -C ${mnt:?}/usr/src DESTDIR=${WRKDIR:?}/world BATCH_DELETE_OLD_FILES=yes SRCCONF=${WRKDIR:?}/src.conf delete-old delete-old-libs
	msg "Installing world done"
}

HOSTNAME=poudriere-image
INSTALLWORLD=install_world
PKG_QUIET="-q"

: ${PRE_BUILD_SCRIPT:=""}
: ${POST_BUILD_SCRIPT:=""}

while getopts "A:bB:c:f:h:i:j:m:n:o:p:P:R:s:S:t:vw:X:z:" FLAG; do
	case "${FLAG}" in
		A)
			[ "${OPTARG#/}" = "${OPTARG}" ] && \
			    OPTARG="${SAVED_PWD}/${OPTARG}"
			[ -f "${OPTARG}" ] || err 1 "No such post-build-script: ${OPTARG}"
			POST_BUILD_SCRIPT="$(realpath ${OPTARG})"
			;;
		b)
			SWAPBEFORE=1
			;;
		B)
			[ "${OPTARG#/}" = "${OPTARG}" ] && \
			    OPTARG="${SAVED_PWD}/${OPTARG}"
			[ -f "${OPTARG}" ] || err 1 "No such pre-build-script: ${OPTARG}"
			PRE_BUILD_SCRIPT="$(realpath ${OPTARG})"
			;;
		c)
			[ "${OPTARG#/}" = "${OPTARG}" ] && \
			    OPTARG="${SAVED_PWD}/${OPTARG}"
			[ -d "${OPTARG}" ] || err 1 "No such extract directory: ${OPTARG}"
			EXTRADIR=$(realpath "${OPTARG}")
			;;
		f)
			# If this is a relative path, add in ${PWD} as
			# a cd / was done.
			[ "${OPTARG#/}" = "${OPTARG}" ] && \
			    OPTARG="${SAVED_PWD}/${OPTARG}"
			[ -r "${OPTARG}" ] || err 1 "No such package list: ${OPTARG}"
			PACKAGELIST=${OPTARG}
			;;
		h)
			HOSTNAME=${OPTARG}
			;;
		i)
			ORIGIN_IMAGE=${OPTARG}
			;;
		j)
			JAILNAME=${OPTARG}
			;;
		m)
			[ "${OPTARG#/}" = "${OPTARG}" ] && \
			    OPTARG="${SAVED_PWD}/${OPTARG}"
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
		P)
			# If this is a relative path, add in ${PWD} as
			# a cd / was done.
			[ "${OPTARG#/}" = "${OPTARG}" ] && \
			    OPTARG="${SAVED_PWD}/${OPTARG}"
			[ -r "${OPTARG}" ] || err 1 "No such package list: ${OPTARG}"
			PKGBASELIST=${OPTARG}
			INSTALLWORLD=install_world_from_pkgbase
			;;
		R)
			ZFS_SEND_FLAGS="-${OPTARG}"
			;;
		s)
			IMAGESIZE="${OPTARG}"
			;;
		S)
			SNAPSHOT_NAME="${OPTARG}"
			;;
		t)
			MEDIATYPE=${OPTARG}
			case ${MEDIATYPE} in
			hybridiso|iso|iso+mfs|iso+zmfs|usb|usb+mfs|usb+zmfs) ;;
			rawdisk|zrawdisk|tar|firmware|rawfirmware) ;;
			dump|zsnapshot) ;;
			zfs|zfs+gpt|zfs+raw) ;;
			zfs+send|zfs+send+full|zfs+send+be|zfs+send+full+be) ;;
			*) err 1 "invalid mediatype: ${MEDIATYPE}"
			esac
			;;
		v)
			PKG_QUIET=""
			;;
		w)
			SWAPSIZE="${OPTARG}"
			;;
		X)
			# If this is a relative path, add in ${PWD} as
			# a cd / was done.
			[ "${OPTARG#/}" = "${OPTARG}" ] && \
			OPTARG="${SAVED_PWD}/${OPTARG}"
			[ -r "${OPTARG}" ] || err 1 "No such exclude list ${OPTARG}"
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

encode_args saved_argv "$@"
shift $((OPTIND-1))
post_getopts

[ -n "${JAILNAME}" ] || usage

: ${OUTPUTDIR:=${POUDRIERE_DATA}/images}
: ${IMAGENAME:=poudriereimage}
: ${MEDIATYPE:=none}
: ${SWAPBEFORE:=0}
: ${SWAPSIZE:=0}
: ${PTNAME:=default}
: ${ZFS_SEND_FLAGS:=-Rec}
: ${ZFS_POOL_NAME:=zroot}
: ${ZFS_BEROOT_NAME:=ROOT}
: ${ZFS_BOOTFS_NAME:=default}

MASTERNAME=${JAILNAME}-${PTNAME}${SETNAME:+-${SETNAME}}

MAINMEDIATYPE=${MEDIATYPE%%+*}
MEDIAREMAINDER=${MEDIATYPE#*+}
SUBMEDIATYPE=${MEDIAREMAINDER%%+*}
MEDIAREMAINDER=${MEDIAREMAINDER#*+}

if [ "${MEDIATYPE}" = "none" ]; then
	err 1 "Missing -t option"
fi

${MAINMEDIATYPE}_check ${SUBMEDIATYPE} || err 1 "${MAINMEDIATYPE}_check failed"

mkdir -p "${OUTPUTDIR}"

jail_exists ${JAILNAME} || err 1 "The jail ${JAILNAME} does not exist"
_jget arch ${JAILNAME} arch || err 1 "Missing arch metadata for jail"
_jget mnt ${JAILNAME} mnt || err 1 "Missing mnt metadata for jail"
get_host_arch host_arch

msg "Preparing the image '${IMAGENAME}'"
md=""
CLEANUP_HOOK=cleanup_image
[ -d "${POUDRIERE_DATA}/images" ] || \
    mkdir "${POUDRIERE_DATA:?}/images"
WRKDIR=$(mktemp -d ${POUDRIERE_DATA}/images/${IMAGENAME}-XXXX)
if [ "${TMPFS_IMAGE:-0}" -eq 1 -o "${TMPFS_ALL}" -eq 1 ]; then
	mnt_tmpfs image "${WRKDIR:?}"
fi
_jget mnt ${JAILNAME} mnt || err 1 "Missing mnt metadata for jail"
excludelist=$(mktemp -t excludelist)
mkdir -p ${WRKDIR:?}/world
mkdir -p ${WRKDIR:?}/out
WORLDDIR="${WRKDIR:?}/world"
[ -z "${EXCLUDELIST}" ] || cat ${EXCLUDELIST:?} > ${excludelist:?}
cat >> ${excludelist:?} << EOF
.poudriere-snap-*
usr/src
var/db/freebsd-update
var/db/etcupdate
boot/kernel.old
nxb-bin
EOF

# Need to convert IMAGESIZE from bytes to bibytes
# This conversion is needed to be compliant with marketing 'unit'
# without this, a 2GiB image will not fit into a 2GB flash disk (=1862MiB)

if [ -n "${IMAGESIZE}" ]; then
	IMAGESIZE_UNIT=$(printf "%s" "${IMAGESIZE}" | tail -c 1)
	IMAGESIZE_VALUE=${IMAGESIZE%?}
	NEW_IMAGESIZE_UNIT=""
	NEW_IMAGESIZE_SIZE=""
	case "${IMAGESIZE_UNIT}" in
		k|K)
			err 1 "Need a bigger image size than kilobyte"
			;;
		m|M)
			DIVIDER=$(echo "scale=6; 1024 / 1000" | bc)
			NEW_IMAGESIZE_UNIT="m"
			;;
		g|G)
			DIVIDER=$(echo "scale=9; 1024 / (1000 * 1000)" | bc)
			NEW_IMAGESIZE_UNIT="m"
			;;
		t|T)
			DIVIDER=$(echo "scale=12; 1024 / (1000 * 1000 * 1000)" | bc)
			NEW_IMAGESIZE_UNIT="m"
			;;
		*)
			err 1 "Image size need a unit (m/g/t)"
			;;
	esac
	# truncate accept only integer value, and bc needs a divide per 1 for refreshing scale
	[ -z "${NEW_IMAGESIZE_SIZE}" ] && NEW_IMAGESIZE_SIZE=$(echo "scale=9;var=${IMAGESIZE_VALUE} / ${DIVIDER}; scale=0; var / 1" | bc)
	IMAGESIZE="${NEW_IMAGESIZE_SIZE}${NEW_IMAGESIZE_UNIT}"
	msg "Calculated image size ${IMAGESIZE}"
fi

if [ -n "${SWAPSIZE}" ]; then
	SWAPSIZE_UNIT=$(printf "%s" "${SWAPSIZE}" | tail -c 1)
	SWAPSIZE_VALUE=${SWAPSIZE%?}
	NEW_SWAPSIZE_UNIT=""
	NEW_SWAPSIZE_SIZE=""
	case "${SWAPSIZE_UNIT}" in
		k|K)
			err 1 "Need a bigger image size than kilobyte"
			;;
		m|M)
			DIVIDER=$(echo "scale=6; 1024 * 1024 / 1000000" | bc)
			NEW_SWAPSIZE_UNIT="k"
			;;
		g|G)
			DIVIDER=$(echo "scale=9; 1024 * 1024 * 1024 / 1000000000" | bc)
			NEW_SWAPSIZE_UNIT="m"
			;;
		t|T)
			DIVIDER=$(echo "scale=12; 1024 * 1024 * 1024 * 1024 / 1000000000000" | bc)
			NEW_SWAPSIZE_UNIT="g"
			;;
		*)
			NEW_SWAPSIZE_UNIT=""
			NEW_SWAPSIZE_SIZE=${SWAPSIZE}
	esac
	# truncate accept only integer value, and bc needs a divide per 1 for refreshing scale
	[ -z "${NEW_SWAPSIZE_SIZE}" ] && NEW_SWAPSIZE_SIZE=$(echo "scale=9;var=${SWAPSIZE_VALUE} / ${DIVIDER}; scale=0; ( var * 1000 ) /1" | bc)
	SWAPSIZE="${NEW_SWAPSIZE_SIZE}${NEW_SWAPSIZE_UNIT}"
fi

SKIP_PREPARE=
if [ -n "${PRE_BUILD_SCRIPT}" ]; then
	. "${PRE_BUILD_SCRIPT}"
fi

if [ -z "$SKIP_PREPARE" ]; then
	${MAINMEDIATYPE}_prepare ${SUBMEDIATYPE} || err 1 "${MAINMEDIATYPE}_prepare failed"
fi

# Run the install world function
${INSTALLWORLD}

[ ! -d "${EXTRADIR}" ] || cp -fRPp "${EXTRADIR:?}/" ${WRKDIR:?}/world/
if [ -f "${WRKDIR}/world/etc/login.conf.orig" ]; then
	mv -f "${WRKDIR:?}/world/etc/login.conf.orig" \
	    "${WRKDIR:?}/world/etc/login.conf"
fi
cap_mkdb ${WRKDIR:?}/world/etc/login.conf
pwd_mkdb -d ${WRKDIR:?}/world/etc -p ${WRKDIR:?}/world/etc/master.passwd

# Set hostname
if [ -n "${HOSTNAME}" ]; then
	# `sysrc -R` tries to run a shell inside the chroot(8).
	# It may fail if the target is on a different architecture than the host.
	# In this case, set /etc/rc.conf as the destination for the hostname.
	if [ "${arch}" == "${host_arch}" ]; then
		sysrc -q -R "${WRKDIR:?}/world" hostname="${HOSTNAME}"
	else
		sysrc -q -f "${WRKDIR:?}/world/etc/rc.conf" hostname="${HOSTNAME}"
	fi
fi

msg "Installing packages"
# install packages if any is needed
if [ -n "${PACKAGELIST}" ]; then
	mkdir -p ${WRKDIR:?}/world/tmp/packages
	${NULLMOUNT} ${POUDRIERE_DATA:?}/packages/${MASTERNAME} ${WRKDIR:?}/world/tmp/packages
	if [ "${arch}" == "${host_arch}" ]; then
		cat > "${WRKDIR:?}/world/tmp/repo.conf" <<-EOF
		FreeBSD: { enabled: false }
		local: { url: file:///tmp/packages }
		EOF
		convert_package_list "${PACKAGELIST}" | \
		    xargs chroot "${WRKDIR}/world" env \
		    REPOS_DIR=/tmp ASSUME_ALWAYS_YES=yes \
		    pkg install
	else
		cat > "${WRKDIR:?}/world/tmp/repo.conf" <<-EOF
		FreeBSD: { enabled: false }
		local: { url: file:///${WRKDIR}/world/tmp/packages }
		EOF
		(
			export ASSUME_ALWAYS_YES=yes SYSLOG=no \
			    REPOS_DIR="${WRKDIR}/world/tmp/" \
			    ABI_FILE="${WRKDIR}/world/usr/lib/crt1.o"
			pkg -r "${WRKDIR:?}/world/" install pkg
			convert_package_list "${PACKAGELIST}" | \
			    xargs pkg -r "${WRKDIR:?}/world/" install
		)
	fi
	rm -rf ${WRKDIR:?}/world/var/cache/pkg
	umount ${WRKDIR:?}/world/tmp/packages
	rmdir ${WRKDIR:?}/world/tmp/packages
	rm ${WRKDIR:?}/world/var/db/pkg/repo-* 2>/dev/null || :
fi

if [ -f "${EXTRADIR}".mtree ]; then
	# This file could be created with:
	# mtree -bcjn -F freebsd9 -k uname,gname,mode -p $EXTRADIR > $EXTRADIR.mtree
	# And must be applyied after installing packages to declare packages’
	# users and groups
	chroot "${WRKDIR}/world" mtree -eiU <"${EXTRADIR}".mtree
fi

if [ -f "${POST_BUILD_SCRIPT}" ]; then
	# Source the post-build-script.
	. "${POST_BUILD_SCRIPT}"
fi

${MAINMEDIATYPE}_build ${SUBMEDIATYPE} || err 1 "${MAINMEDIATYPE}_build failed"

${MAINMEDIATYPE}_generate ${SUBMEDIATYPE} || err 1 "${MAINMEDIATYPE}_generate failed"

CLEANUP_HOOK=delete_image
msg "Image available at: ${OUTPUTDIR}/${FINALIMAGE}"
