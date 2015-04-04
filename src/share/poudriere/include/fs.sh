# Copyright (c) 2010-2013 Baptiste Daroussin <bapt@FreeBSD.org>
# Copyright (c) 2012-2014 Bryan Drewery <bdrewery@FreeBSD.org>
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

createfs() {
	[ $# -ne 3 ] && eargs createfs name mnt fs
	local name mnt fs
	name=$1
	mnt=$(echo $2 | sed -e "s,//,/,g")
	fs=$3

	[ -z "${NO_ZFS}" ] || fs=none

	if [ -n "${fs}" -a "${fs}" != "none" ]; then
		msg_n "Creating ${name} fs..."
		zfs create -p \
			-o compression=lz4 \
			-o atime=off \
			-o mountpoint=${mnt} ${fs} || err 1 " fail"
		echo " done"
	else
		mkdir -p ${mnt}
	fi
}

do_clone() {
	cpdup -i0 -x "${1}" "${2}"
}

rollbackfs() {
	[ $# -lt 2 ] && eargs rollbackfs name mnt [fs]
	local name=$1
	local mnt=$2
	local fs="${3:-$(zfs_getfs ${mnt})}"

	if [ -n "${fs}" ]; then
		zfs rollback -r "${fs}@${name}" || \
		    err 1 "Unable to rollback ${fs}"
		return
	fi

	do_clone "${MASTERMNT}" "${mnt}"
}

umountfs() {
	[ $# -lt 1 ] && eargs umountfs mnt childonly
	local mnt=$1
	local childonly=$2
	local pattern

	[ -n "${childonly}" ] && pattern="/"

	[ -d "${mnt}" ] || return 0
	mnt=$(realpath ${mnt})
	mount | sort -r -k 2 | while read dev on pt opts; do
		case ${pt} in
		${mnt}${pattern}*)
			umount -f ${pt} || :
			[ "${dev#/dev/md*}" != "${dev}" ] && mdconfig -d -u ${dev#/dev/md*}
		;;
		esac
	done

	return 0
}

zfs_getfs() {
	[ $# -ne 1 ] && eargs zfs_getfs mnt
	local mnt=$(realpath $1)
	mount -t zfs | awk -v n="${mnt}" ' $3 == n { print $1 }'
}

mnt_tmpfs() {
	[ $# -lt 2 ] && eargs mnt_tmpfs type dst
	local type="$1"
	local dst="$2"
	local limit size

	case ${type} in
		data)
			# Limit data to 1GiB
			limit=1
			;;

		*)
			limit=${TMPFS_LIMIT}
			;;
	esac

	[ -n "${limit}" ] && size="-o size=${limit}G"

	mount -t tmpfs ${size} tmpfs "${dst}"
}

clonefs() {
	[ $# -ne 3 ] && eargs clonefs from to snap
	local from=$1
	local to=$2
	local snap=$3
	local name zfs_to
	local fs=$(zfs_getfs ${from})

	destroyfs ${to} jail
	mkdir -p ${to}
	to=$(realpath ${to})
	# When using TMPFS, there is no need to clone the originating FS from
	# a snapshot as the destination will be tmpfs. We do however need to
	# ensure the originating FS is rolled back to the expected snapshot.
	if [ -n "${fs}" -a ${TMPFS_ALL} -eq 1 ]; then
		rollbackfs "${snap}" "${from}" "${fs}"
		unset fs
	fi
	if [ -n "${fs}" ]; then
		name=${to##*/}

		if [ "${name}" = "ref" ]; then
			zfs_to=${fs%/*}/${MASTERNAME}-${name}
		else
			zfs_to=${fs}/${name}
		fi

		zfs clone -o mountpoint=${to} \
			-o sync=disabled \
			-o atime=off \
			-o compression=off \
			${fs}@${snap} \
			${zfs_to}
	else
		[ ${TMPFS_ALL} -eq 1 ] && mnt_tmpfs all ${to}
		if [ "${snap}" = "clean" ]; then
			echo "src" >> "${from}/usr/.cpignore" || :
			echo "debug" >> "${from}/usr/lib/.cpignore" || :
		fi
		do_clone "${from}" "${to}"
		if [ "${snap}" = "clean" ]; then
			rm -f "${from}/usr/.cpignore" \
			    "${from}/usr/lib/.cpignore"
			echo ".p" >> "${to}/.cpignore"
		fi
	fi
}

destroyfs() {
	[ $# -ne 2 ] && eargs destroyfs name type
	local mnt fs type
	mnt=$1
	type=$2
	[ -d ${mnt} ] || return 0
	mnt=$(realpath ${mnt})
	fs=$(zfs_getfs ${mnt})
	umountfs ${mnt} 1
	if [ ${TMPFS_ALL} -eq 1 ]; then
		umount -f ${mnt} 2>/dev/null || :
	elif [ -n "${fs}" -a "${fs}" != "none" ]; then
		zfs destroy -rf ${fs}
		rmdir ${mnt}
	else
		chflags -R noschg ${mnt}
		rm -rf ${mnt}
	fi
}
