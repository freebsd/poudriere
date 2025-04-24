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
			-o compression=on \
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

_do_cpdup() {
	[ $# -eq 4 ] || eargs _do_cpdup rflags cpignore src dst
	local rflags="$1"
	local cpignore="$2"
	local src="$3"
	local dst="$4"

	if [ "${src}" = "/" -o "${dst}" = "/" ]; then
		err 1 "Tried to cpdup /; src=${src} dst=${dst}"
	fi

	mkdir -p "${dst%/*}"
	cpdup -i0 ${rflags} ${cpignore} "${src}" "${dst}"
}

_do_clone() {
	local -; set -f
	[ $# -lt 3 ] && eargs _do_clone rflags args...
	local rflags="$1"
	shift
	local src dst common relative cpignore FLAG
	local OPTIND=1

	relative=0
	cpignore=""
	while getopts "rxX:" FLAG; do
		case "${FLAG}" in
			r) relative=1 ;;
			x) cpignore="-x" ;;
			X) cpignore="-X ${OPTARG}" ;;
			*) err 1 "_do_clone: Invalid flag" ;;
		esac
	done
	shift $((OPTIND-1))
	[ $# -eq 2 ] || eargs _do_clone rflags args...
	src="$1"
	dst="$2"

	if [ ${relative} -eq 1 ]; then
		set -- $(relpath_common "${src}" "${dst}")
		common="${1}"
		src="${2}"
		dst="${3}"
		if [ "${common}" = "/" ] &&
			[ "${src}" = "." -o "${dst}" = "." ]; then
			err 1 "Tried to cpdup /; common=${common} src=${src} dst=${dst}"
		fi
		(
			cd "${common}" || err 1 "Cannot chdir ${common}"
			_do_cpdup "${rflags}" "${cpignore}" "${src}" "${dst}"
		)
		return
	fi

	_do_cpdup "${rflags}" "${cpignore}" "${src}" "${dst}"
}

do_clone() {
	[ $# -lt 2 ] && eargs do_clone [-r] [-x | -X cpignore ] src dst

	_do_clone "-o" "$@"
}

do_clone_del() {
	[ $# -lt 2 ] && eargs do_clone_del [-r] [-x | -X cpignore ] src dst

	_do_clone "-s0 -f" "$@"
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
			# Success
			if zfs rollback -r "${fs}@${name}" && \
			    ! [ -f "${sfile}" ]; then
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

	do_clone_del -rx "${MASTERMNT}" "${mnt}"
}

findmounts() {
	local mnt="$1"
	local pattern="$2"

	mount | awk -v mnt="${mnt}${pattern}" '$3 ~ mnt {print $1 " " $3}' | \
	    sort -r -k 2 | \
	    while mapfile_read_loop_redir dev pt; do
		if [ "${dev#/dev/md*}" != "${dev}" ]; then
			umount -n "${pt}" || \
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
	local pattern

	[ -n "${childonly}" ] && pattern="/"

	mnt=$(realpath "${mnt}" 2>/dev/null || echo "${mnt}")
	if ! findmounts "${mnt}" "${pattern}" | \
	    xargs umount -n; then
		findmounts "${mnt}" "${pattern}" | xargs umount -fv || :
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
			# Limit data to 2GiB
			limit=2
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
	local fs mnt

	fs=$(zfs_getfs ${from})
	destroyfs ${to} jail
	mkdir -p ${to}
	mnt=$(realpath "${to}")
	# When using TMPFS, there is no need to clone the originating FS from
	# a snapshot as the destination will be tmpfs. We do however need to
	# ensure the originating FS is rolled back to the expected snapshot.
	if [ -n "${fs}" -a ${TMPFS_ALL} -eq 1 ]; then
		rollbackfs "${snap}" "${from}" "${fs}"
		unset fs
	fi
	if [ -n "${fs}" ]; then
		name="${mnt##*/}"

		if [ "${name}" = "ref" ]; then
			zfs_to=${fs%/*}/${MASTERNAME}-${name}
		else
			zfs_to=${fs}/${name}
		fi

		zfs clone -o mountpoint=${mnt} \
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
		local cpignore

		cpignore=
		[ ${TMPFS_ALL} -eq 1 ] && mnt_tmpfs all "${mnt}"
		if [ "${snap}" = "clean" ]; then
			local skippath skippaths common src dst

			set -- $(relpath_common "${from}" "${mnt}")
			common="${1}"
			src="${2}"
			dst="${3}"

			cpignore="$(mktemp -ut clone.cpignore)"
			skippaths="$(nullfs_paths "${mnt}")"
			skippaths="${skippaths} /proc"
			skippaths="${skippaths} /usr/src"
			skippaths="${skippaths} /usr/lib/debug"
			skippaths="${skippaths} /var/db/etcupdate"
			skippaths="${skippaths} /var/db/freebsd-update"
			{
				for skippath in ${skippaths}; do
					echo "${src}${skippath}"
				done
				echo ".cpignore"
			} > "${cpignore}"
		fi
		do_clone -r ${cpignore:+-X "${cpignore}"} "${from}" "${mnt}"
		if [ "${snap}" = "clean" ]; then
			rm -f "${cpignore}"
			echo "${DATADIR_NAME}" >> "${mnt}/.cpignore"
		fi
	fi
}

nullfs_paths() {
	[ $# -eq 1 ] || eargs nullfs_paths mnt
	local mnt="${1}"
	local nullpaths

	nullpaths="${NULLFS_PATHS}"
	if [ "${IMMUTABLE_BASE}" = "nullfs" ]; then
		# Need to keep /usr/src and /usr/ports on their own.
		nullpaths="${nullpaths} /usr/bin /usr/include /usr/lib"
		nullpaths="${nullpaths} /usr/lib32 /usr/libdata /usr/libexec"
		nullpaths="${nullpaths} /usr/obj /usr/sbin /boot /bin /lib"
		nullpaths="${nullpaths} /libexec"
		# Can only add /sbin if not using static ccache
		if [ -z "${CCACHE_STATIC_PREFIX}" ]; then
			nullpaths="${nullpaths} /sbin"
		fi
	fi
	echo "${nullpaths}" | tr ' ' '\n' | sort -u
}

destroyfs() {
	[ $# -ne 2 ] && eargs destroyfs mnt type
	local mnt="$1"
	local type="$2"
	local fs

	umountfs ${mnt} 1
	if [ ${TMPFS_ALL} -eq 1 ]; then
		if [ -d "${mnt}" ]; then
			if ! umount -n "${mnt}" 2>/dev/null; then
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
