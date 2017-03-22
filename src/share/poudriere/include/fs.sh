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
	[ $# -lt 2 ] && eargs do_clone [-r] src dst
	[ $# -gt 3 ] && eargs do_clone [-r] src dst
	local src dst common relative FLAG

	relative=0
	while getopts "r" FLAG; do
		case "${FLAG}" in
			r) relative=1 ;;
		esac
	done
	shift $((OPTIND-1))

	if [ ${relative} -eq 1 ]; then
		set -- $(relpath "${1}" "${2}")
		common="${1}"
		src="${2}"
		dst="${3}"
		(
			cd "${common}"
			cpdup -i0 -x "${src}" "${dst}"
		)
	else
		cpdup -i0 -x "${1}" "${2}"
	fi
}

rollback_file() {
	[ $# -eq 3 ] || eargs rollback_file mnt snapshot var_return
	local mnt="$1"
	local snapshot="$2"
	local var_return="$3"

	setvar "${var_return}" "${mnt}/.poudriere-snap-${snapshot}"
}

rollbackfs() {
	[ $# -lt 2 ] && eargs rollbackfs name mnt [fs]
	local name=$1
	local mnt=$2
	local fs="${3-$(zfs_getfs ${mnt})}"
	local sfile tries

	if [ -n "${fs}" ]; then
		# ZFS has a race with rollback+snapshot.  If ran concurrently
		# it is possible that the rollback will "succeed" but the
		# dataset will be on the newly created snapshot.  Avoid this
		# by creating a file that we know won't be in the expected
		# snapshot and trying a few times before considering it a
		# failure.  https://www.illumos.org/issues/7600
		rollback_file "${mnt}" "${name}" sfile
		# The file should already exist from a markfs call.  If it
		# doesn't for some reason, make it here.  The reason
		# for markfs to create it is to avoid just hitting race that
		# this extra code is trying to avoid in the first place.
		if ! [ -f "${sfile}" ] && ! : > "${sfile}"; then
			# Cannot create our race check file, so just try
			# and assume it is OK.
			zfs rollback -r "${fs}@${name}" || \
			    err 1 "Unable to rollback ${fs}"
			: > "${sfile}" || :
			return
		fi
		tries=0
		while :; do
			if ! zfs rollback -r "${fs}@${name}"; then
				rm -f "${sfile}"
				err 1 "Unable to rollback ${fs} to ${name}"
			fi
			# Success
			if ! [ -f "${sfile}" ]; then
				break
			fi
			tries=$((tries + 1))
			if [ ${tries} -eq 20 ]; then
				rm -f "${sfile}"
				err 1 "Timeout rolling back ${fs} to ${name}"
			fi
			sleep 1
		done
		# Need to create the file to note which snapshot we're in.
		: > "${sfile}"
		return
	fi

	do_clone -r "${MASTERMNT}" "${mnt}"
}

findmounts() {
	local mnt="$1"
	local pattern="$2"

	mount | sort -r -k 2 | while read dev on pt opts; do
		case "${pt}" in
		${mnt}${pattern}*)
			if [ "${dev#/dev/md*}" != "${dev}" ]; then
				umount ${UMOUNT_NONBUSY} "${pt}" || \
				    umount -f "${pt}" || :
				mdconfig -d -u ${dev#/dev/md*}
			else
				echo "${pt}"
			fi
		;;
		esac
	done
}

umountfs() {
	[ $# -lt 1 ] && eargs umountfs mnt childonly
	local mnt=$1
	local childonly=$2
	local pattern xargsmax

	[ -n "${childonly}" ] && pattern="/"

	mnt=$(realpath "${mnt}" 2>/dev/null || echo "${mnt}")
	xargsmax=
	if [ ${UMOUNT_BATCHING} -eq 0 ]; then
		xargsmax="-n 2"
	fi
	if ! findmounts "${mnt}" "${pattern}" | \
	    xargs ${xargsmax} umount ${UMOUNT_NONBUSY}; then
		findmounts "${mnt}" "${pattern}" | xargs ${xargsmax} umount -fv || :
	fi

	return 0
}

zfs_getfs() {
	[ $# -ne 1 ] && eargs zfs_getfs mnt
	local mnt="${1}"
	local mntres

	mntres=$(realpath "${mnt}" 2>/dev/null || echo "${mnt}")
	mount -t zfs | awk -v n="${mntres}" ' $3 == n { print $1 }'
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
			echo "freebsd-update" >> "${from}/var/db/.cpignore" || :
		fi
		do_clone -r "${from}" "${to}"
		if [ "${snap}" = "clean" ]; then
			rm -f "${from}/usr/.cpignore" \
			    "${from}/usr/lib/.cpignore" \
			    "${from}/var/db/.cpignore"
			echo ".p" >> "${to}/.cpignore"
		fi
	fi
	# Create our data dir.
	mkdir -p "${to}/.p"
}

destroyfs() {
	[ $# -ne 2 ] && eargs destroyfs name type
	local mnt="$1"
	local type="$2"
	local fs

	fs=$(zfs_getfs ${mnt})
	umountfs ${mnt} 1
	if [ ${TMPFS_ALL} -eq 1 ]; then
		if [ -d "${mnt}" ]; then
			if ! umount ${UMOUNT_NONBUSY} "${mnt}" 2>/dev/null; then
				umount -f "${mnt}" 2>/dev/null || :
			fi
		fi
	elif [ -n "${fs}" -a "${fs}" != "none" ]; then
		zfs destroy -rf ${fs}
		rmdir ${mnt} || :
	else
		[ -d ${mnt} ] || return 0
		rm -rfx ${mnt} 2>/dev/null || :
		if [ -d "${mnt}" ]; then
			chflags -R 0 ${mnt}
			rm -rfx ${mnt}
		fi
	fi
}
