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
		msg_n "Creating ${name} fs at ${mnt}..."
		if ! zfs create -p \
			-o compression=lz4 \
			-o atime=off \
			-o mountpoint=${mnt} ${fs}; then
			echo " fail"
			err 1 "Failed to create FS ${fs}"
		fi
		echo " done"
		# Must invalidate the zfs_getfs cache now in case of a
		# negative entry.
		cache_invalidate _zfs_getfs "${mnt}"
	else
		msg_n "Creating ${name} fs at ${mnt}..."
		if ! mkdir -p "${mnt}"; then
			echo " fail"
			err 1 "Failed to create directory ${mnt}"
		fi
		# If the directory is non-empty then we didn't create it.
		if ! dirempty "${mnt}"; then
			echo " fail"
			err 1 "Directory not empty at ${mnt}"
		fi
		echo " done"
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
		set -- $(relpath_common "${1}" "${2}")
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
				unlink "${sfile}"
				err 1 "Unable to rollback ${fs} to ${name}"
			fi
			# Success
			if ! [ -f "${sfile}" ]; then
				break
			fi
			tries=$((tries + 1))
			if [ ${tries} -eq 20 ]; then
				unlink "${sfile}"
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

	mount | awk -v mnt="${mnt}${pattern}" '$3 ~ mnt {print $1 " " $3}' | \
	    sort -r -k 2 | \
	    while read dev pt; do
		if [ "${dev#/dev/md*}" != "${dev}" ]; then
			umount ${UMOUNT_NONBUSY} "${pt}" || \
			    umount -f "${pt}" || :
			mdconfig -d -u ${dev#/dev/md*}
		else
			echo "${pt}"
		fi
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

_zfs_getfs() {
	[ $# -ne 1 ] && eargs _zfs_getfs mnt
	local mnt="${1}"

	mntres=$(realpath "${mnt}" 2>/dev/null || echo "${mnt}")
	zfs list -rt filesystem -H -o name,mountpoint ${ZPOOL}${ZROOTFS} | \
	    awk -vmnt="${mntres}" '$2 == mnt {print $1}'
}

zfs_getfs() {
	[ $# -ne 1 ] && eargs zfs_getfs mnt
	local mnt="${1}"
	local value

	[ -n "${NO_ZFS}" ] && return 0
	[ -z "${ZPOOL}${ZROOTFS}" ] && return 0

	cache_call value _zfs_getfs "${mnt}"
	if [ -n "${value}" ]; then
		echo "${value}"
	fi
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
	local basepath dir dirs skippaths cpignore cpignores

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
		# Must invalidate the zfs_getfs cache now in case of a
		# negative entry.
		cache_invalidate _zfs_getfs "${to}"
		# Insert this into the zfs_getfs cache.
		cache_set "${zfs_to}" _zfs_getfs "${to}"
	else
		[ ${TMPFS_ALL} -eq 1 ] && mnt_tmpfs all ${to}
		if [ "${snap}" = "clean" ]; then
			skippaths="$(nullfs_paths "${to}")"
			skippaths="${skippaths} /usr/src"
			skippaths="${skippaths} /usr/lib/debug"
			skippaths="${skippaths} /var/db/etcupdate"
			skippaths="${skippaths} /var/db/freebsd-update"
			while read basepath dirs; do
				cpignore="${from}${basepath%/}/.cpignore"
				for dir in ${dirs}; do
					echo "${dir}"
				done >> "${cpignore}"
				cpignores="${cpignores:+${cpignores} }${cpignore}"
			done <<-EOF
			$(echo "${skippaths}" | tr ' ' '\n' | \
			    sed '/^$/d' | awk '
			    function basename(file) {
				    sub(".*/", "", file)
				    return file
			    }
			    function dirname(file) {
				    sub("/[^/]*$", "", file)
				    if (file == "")
					    file = "/"
				    return file
			    }
			    {
				    dir = dirname($1)
				    file = basename($1)
				    if (dir in dirs)
					    dirs[dir] = dirs[dir] " " file
				    else
					    dirs[dir] = file
			    }
			    END {
				    for (dir in dirs)
					    print dir " " dirs[dir]
			    }')
			EOF
		fi
		do_clone -r "${from}" "${to}"
		if [ "${snap}" = "clean" ]; then
			rm -f ${cpignores}
			echo ".p" >> "${to}/.cpignore"
		fi
	fi
	# Create our data dir.
	mkdir -p "${to}/.p"
}

nullfs_paths() {
	[ $# -eq 1 ] || eargs nullfs_paths mnt
	local mnt="${1}"
	local nullpaths

	nullpaths="/rescue /usr/share /usr/tests /usr/lib32"
	if [ "${MUTABLE_BASE}" = "no" ]; then
		# Need to keep /usr/src and /usr/ports on their own.
		nullpaths="${nullpaths} /usr/bin /usr/include /usr/lib \
		    /usr/lib32 /usr/libdata /usr/libexec /usr/obj \
		    /usr/sbin /boot /bin /sbin /lib \
		    /libexec"
		# Do a real copy for the ref jail since we need to modify
		# or create directories in them.
		if [ "${mnt##*/}" != "ref" ]; then
			nullpaths="${nullpaths} /etc"
		fi
	fi
	echo "${nullpaths}"
}

destroyfs() {
	[ $# -ne 2 ] && eargs destroyfs name type
	local mnt="$1"
	local type="$2"
	local fs

	umountfs ${mnt} 1
	if [ ${TMPFS_ALL} -eq 1 ]; then
		if [ -d "${mnt}" ]; then
			if ! umount ${UMOUNT_NONBUSY} "${mnt}" 2>/dev/null; then
				umount -f "${mnt}" 2>/dev/null || :
			fi
		fi
	else
		[ "${fs}" != "none" ] && fs=$(zfs_getfs ${mnt})
		if [ -n "${fs}" -a "${fs}" != "none" ]; then
			zfs destroy -rf ${fs}
			rmdir ${mnt} || :
			# Must invalidate the zfs_getfs cache.
			cache_invalidate _zfs_getfs "${mnt}"
		else
			[ -d ${mnt} ] || return 0
			rm -rfx ${mnt} 2>/dev/null || :
			if [ -d "${mnt}" ]; then
				chflags -R 0 ${mnt}
				rm -rfx ${mnt}
			fi
		fi
	fi
}
