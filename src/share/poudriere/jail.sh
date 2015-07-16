#!/bin/sh
# 
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

usage() {
	[ $# -gt 0 ] && echo "Missing: $@" >&2
	cat << EOF
poudriere jail [parameters] [options]

Parameters:
    -c            -- Create a jail
    -d            -- Delete a jail
    -i            -- Show information about a jail
    -l            -- List all available jails
    -s            -- Start a jail
    -k            -- Stop a jail
    -u            -- Update a jail
    -r newname    -- Rename a jail

Options:
    -q            -- Quiet (Do not print the header)
    -n            -- Print only jail name (for use with -l)
    -J n          -- Run buildworld in parallel with n jobs.
    -j jailname   -- Specify the jailname
    -v version    -- Specify which version of FreeBSD to install in the jail.
    -a arch       -- Indicates the TARGET_ARCH of the jail. Such as i386 or
                     amd64. Format of TARGET.TARGET_ARCH is also supported.
                     (Default: same as the host)
    -f fs         -- FS name (tank/jails/myjail) if fs is "none" then do not
                     create on ZFS.
    -M mountpoint -- Mountpoint
    -m method     -- When used with -c, overrides the default method for
                     obtaining and building the jail. See poudriere(8) for more
                     details. Can be one of:
                       allbsd, csup, ftp, http, ftp-archive, null, src, svn,
                       svn+file, svn+http, svn+https, svn+ssh, tar=PATH
                       url=SOMEURL
    -P patch      -- Specify a patch to apply to the source before building.
    -S srcpath    -- Specify a path to the source tree to be used.
    -t version    -- Version of FreeBSD to upgrade the jail to.
    -x            -- Build and setup native-xtools cross compile tools in jail when
                     building for a different TARGET ARCH than the host.
                     Only applies if TARGET_ARCH and HOST_ARCH are different.
                     Will only be used if -m is svn*.

Options for -s and -k:
    -p tree       -- Specify which ports tree to start/stop the jail with.
    -z set        -- Specify which SET the jail to start/stop with.
EOF
	exit 1
}

list_jail() {
	local format
	local j name version arch method mnt timestamp time

	format='%%-%ds %%-%ds %%-%ds %%-%ds %%-%ds %%s'
	display_setup "${format}" 6 "-d -k2,2 -k3,3 -k1,1"
	if [ ${NAMEONLY} -eq 0 ]; then
		display_add "JAILNAME" "VERSION" "ARCH" "METHOD" \
		    "TIMESTAMP" "PATH"
	else
		display_add JAILNAME
	fi
	[ -d ${POUDRIERED}/jails ] || return 0
	for j in $(find ${POUDRIERED}/jails -type d -maxdepth 1 -mindepth 1 -print); do
		name=${j##*/}
		if [ ${NAMEONLY} -eq 0 ]; then
			_jget version ${name} version
			_jget arch ${name} arch
			_jget method ${name} method
			_jget mnt ${name} mnt
			_jget timestamp ${name} timestamp 2>/dev/null || :
			time=
			[ -n "${timestamp}" ] && \
			    time="$(date -j -r ${timestamp} "+%Y-%m-%d %H:%M:%S")"
			display_add "${name}" "${version}" "${arch}" \
			    "${method}" "${time}" "${mnt}"
		else
			display_add ${name}
		fi
	done
	[ ${QUIET} -eq 1 ] && quiet="-q"
	display_output ${quiet}
}

delete_jail() {
	local cache_dir method

	test -z ${JAILNAME} && usage JAILNAME
	jail_exists ${JAILNAME} || err 1 "No such jail: ${JAILNAME}"
	jail_runs ${JAILNAME} &&
		err 1 "Unable to delete jail ${JAILNAME}: it is running"
	msg_n "Removing ${JAILNAME} jail..."
	method=$(jget ${JAILNAME} method)
	if [ "${method}" = "null" ]; then
		mv -f ${JAILMNT}/etc/login.conf.orig \
		    ${JAILMNT}/etc/login.conf
		cap_mkdb ${JAILMNT}/etc/login.conf
	else
		TMPFS_ALL=0 destroyfs ${JAILMNT} jail
	fi
	cache_dir="${POUDRIERE_DATA}/cache/${JAILNAME}-*"
	rm -rf ${POUDRIERED}/jails/${JAILNAME} ${cache_dir} || :
	echo " done"
}

cleanup_new_jail() {
	msg "Error while creating jail, cleaning up." >&2
	delete_jail
}

# Lookup new version from newvers and set in jset version
update_version() {
	local version_extra="$1"

	eval `grep "^[RB][A-Z]*=" ${SRC_BASE}/sys/conf/newvers.sh `
	RELEASE=${REVISION}-${BRANCH}
	[ -n "${version_extra}" ] &&
	    RELEASE="${RELEASE} ${version_extra}"
	jset ${JAILNAME} version "${RELEASE}"
	echo "${RELEASE}"
}

# Set specified version into login.conf
update_version_env() {
	local release="$1"
	local login_env osversion

	osversion=`awk '/\#define __FreeBSD_version/ { print $3 }' ${JAILMNT}/usr/include/sys/param.h`
	login_env=",UNAME_r=${release% *},UNAME_v=FreeBSD ${release},OSVERSION=${osversion}"

	# Tell pkg(8) to not use /bin/sh for the ELF ABI since it is native.
	need_emulation  "${ARCH}" && \
	    login_env="${login_env},ABI_FILE=\/usr\/lib\/crt1.o"

	# Check TARGET=i386 not TARGET_ARCH due to pc98/i386
	need_cross_build "${REALARCH}" "${ARCH}" && \
	    login_env="${login_env},UNAME_m=${ARCH%.*},UNAME_p=${ARCH#*.}"

	sed -i "" -e "s/,UNAME_r.*:/:/ ; s/:\(setenv.*\):/:\1${login_env}:/" ${JAILMNT}/etc/login.conf
	cap_mkdb ${JAILMNT}/etc/login.conf
}

rename_jail() {
	local cache_dir

	jail_exists ${JAILNAME} || err 1 "No such jail: ${JAILNAME}"
	msg_n "Renaming '${JAILNAME}' in '${NEWJAILNAME}'"
	mv ${POUDRIERED}/jails/${JAILNAME} ${POUDRIERED}/jails/${NEWJAILNAME}
	cache_dir="${POUDRIERE_DATA}/cache/${JAILNAME}-*"
	rm -rf ${cache_dir} >/dev/null 2>&1 || :
	echo " done"
	msg_warn "The packages, logs and filesystems have not been renamed."
	msg_warn "If you choose to rename the filesystem then modify the 'mnt' and 'fs' files in ${POUDRIERED}/jails/${NEWJAILNAME}"
}

update_jail() {
	SRC_BASE="${JAILMNT}/usr/src"
	METHOD=$(jget ${JAILNAME} method)
	if [ -z "${METHOD}" -o "${METHOD}" = "-" ]; then
		METHOD="ftp"
		jset ${JAILNAME} method ${METHOD}
	fi
	msg "Upgrading using ${METHOD}"
	case ${METHOD} in
	ftp|http|ftp-archive)
		MASTERMNT=${JAILMNT}
		MASTERNAME=${JAILNAME}-${PTNAME}${SETNAME:+-${SETNAME}}
		[ -n "${RESOLV_CONF}" ] && cp -v "${RESOLV_CONF}" "${JAILMNT}/etc/"
		do_jail_mounts "${JAILMNT}" "${JAILMNT}" "${ARCH}" "${JAILNAME}"
		JNETNAME="n"
		jstart
		# Fix freebsd-update to not check for TTY and to allow
		# EOL branches to still get updates.
		sed \
		    -e 's/! -t 0/1 -eq 0/' \
		    -e 's/-t 0/1 -eq 1/' \
		    -e 's,\(fetch_warn_eol ||\) return 1,\1 :,' \
		    -e 's,sysctl -n kern.bootfile,echo /boot/kernel/kernel,' \
		    ${JAILMNT}/usr/sbin/freebsd-update > \
		    ${JAILMNT}/usr/sbin/freebsd-update.fixed
		chmod +x ${JAILMNT}/usr/sbin/freebsd-update.fixed
		if [ -z "${TORELEASE}" ]; then
			injail env PAGER=/bin/cat \
			    /usr/sbin/freebsd-update.fixed fetch install
		else
			# Install new kernel
			injail env PAGER=/bin/cat \
			    /usr/sbin/freebsd-update.fixed -r ${TORELEASE} \
			    upgrade install || err 1 "Fail to upgrade system"
			# Reboot
			update_version_env ${TORELEASE}
			# Install new world
			injail env PAGER=/bin/cat \
			    /usr/sbin/freebsd-update.fixed install || \
			    err 1 "Fail to upgrade system"
			# Reboot
			update_version_env ${TORELEASE}
			# Remove stale files
			injail env PAGER=/bin/cat \
			    /usr/sbin/freebsd-update.fixed install || :
			jset ${JAILNAME} version ${TORELEASE}
		fi
		rm -f ${JAILMNT}/usr/sbin/freebsd-update.fixed
		jstop
		umountfs ${JAILMNT} 1
		update_version
		[ -n "${RESOLV_CONF}" ] && rm -f ${JAILMNT}/etc/resolv.conf
		update_version_env $(jget ${JAILNAME} version)
		markfs clean ${JAILMNT}
		;;
	csup)
		msg "csup has been deprecated by FreeBSD. Only use if you are syncing with your own csup repo."
		install_from_csup
		update_version_env $(jget ${JAILNAME} version)
		make -C ${SRC_BASE} delete-old delete-old-libs DESTDIR=${JAILMNT} BATCH_DELETE_OLD_FILES=yes
		markfs clean ${JAILMNT}
		;;
	svn*)
		install_from_svn version_extra
		RELEASE=$(update_version "${version_extra}")
		update_version_env "${RELEASE}"
		make -C ${SRC_BASE} delete-old delete-old-libs DESTDIR=${JAILMNT} BATCH_DELETE_OLD_FILES=yes
		markfs clean ${JAILMNT}
		;;
	src=*)
		SRC_BASE="${METHOD#src=}"
		install_from_src
		update_version_env $(jget ${JAILNAME} version)
		make -C ${SRC_BASE} delete-old delete-old-libs DESTDIR=${JAILMNT} BATCH_DELETE_OLD_FILES=yes
		markfs clean ${JAILMNT}
		;;
	allbsd|gjb|url=*)
		[ -z "${VERSION}" ] && VERSION=$(jget ${JAILNAME} version)
		[ -z "${ARCH}" ] && ARCH=$(jget ${JAILNAME} arch)
		delete_jail
		create_jail
		;;
	null|tar)
		err 1 "Upgrade is not supported with ${METHOD}; to upgrade, please delete and recreate the jail"
		;;
	*)
		err 1 "Unsupported method"
		;;
	esac
	jset ${JAILNAME} timestamp $(date +%s)
}

installworld() {
	local destdir="${JAILMNT}"

	msg "Starting make installworld"
	${MAKE_CMD} -C "${SRC_BASE}" installworld DESTDIR=${destdir} \
	    DB_FROM_SRC=1 || err 1 "Failed to 'make installworld'"
	${MAKE_CMD} -C "${SRC_BASE}" DESTDIR=${destdir} DB_FROM_SRC=1 \
	    distrib-dirs || err 1 "Failed to 'make distrib-dirs'"
	${MAKE_CMD} -C "${SRC_BASE}" DESTDIR=${destdir} distribution ||
	    err 1 "Failed to 'make distribution'"

	return 0
}

setup_compat_env() {
	local osversion hostver

	osversion=$(awk '/^\#define[[:blank:]]__FreeBSD_version/ {print $3}' ${SRC_BASE}/sys/sys/param.h)
	hostver=$(awk '/^\#define[[:blank:]]__FreeBSD_version/ {print $3}' /usr/include/sys/param.h)
	MAKE_CMD=make
	if [ ${hostver} -gt 1000000 -a ${osversion} -lt 1000000 ]; then
		FMAKE=$(which fmake 2>/dev/null)
		[ -n "${FMAKE}" ] ||
			err 1 "You need fmake installed on the host: devel/fmake"
		MAKE_CMD=${FMAKE}
	fi

	# Don't enable CCACHE for 10, there are still obscure clang and ld
	# issues
	if [ ${osversion} -lt 1000000 ]; then
		: ${CCACHE_PATH:="/usr/local/libexec/ccache"}
		if [ -n "${CCACHE_DIR}" -a -d ${CCACHE_PATH}/world ]; then
			export CCACHE_DIR
			export CC="${CCACHE_PATH}/world/cc"
			export CXX="${CCACHE_PATH}/world/c++"
			unset CCACHE_TEMPDIR
		fi
	fi
}

build_and_install_world() {
	if [ -n "${EMULATOR}" ]; then
		mkdir -p ${JAILMNT}${EMULATOR%/*}
		cp "${EMULATOR}" "${JAILMNT}${EMULATOR}"
	fi

	export TARGET=${ARCH%.*}
	export TARGET_ARCH=${ARCH#*.}

	export SRC_BASE=${JAILMNT}/usr/src
	mkdir -p ${JAILMNT}/etc
	[ -f ${JAILMNT}/etc/src.conf ] && rm -f ${JAILMNT}/etc/src.conf
	touch ${JAILMNT}/etc/src.conf
	[ -f ${POUDRIERED}/src.conf ] && cat ${POUDRIERED}/src.conf > ${JAILMNT}/etc/src.conf
	[ -n "${SETNAME}" ] && [ -f ${POUDRIERED}/${SETNAME}-src.conf ] && \
	    cat ${POUDRIERED}/${SETNAME}-src.conf >> ${JAILMNT}/etc/src.conf
	[ -f ${POUDRIERED}/${JAILNAME}-src.conf ] && cat ${POUDRIERED}/${JAILNAME}-src.conf >> ${JAILMNT}/etc/src.conf

	if [ "${TARGET}" = "mips" ]; then
		echo "WITH_ELFTOOLCHAIN_TOOLS=y" >> ${JAILMNT}/etc/src.conf
	fi

	unset MAKEOBJPREFIX
	export __MAKE_CONF=/dev/null
	export SRCCONF=${JAILMNT}/etc/src.conf
	MAKE_JOBS="-j${PARALLEL_JOBS}"

	setup_compat_env

	msg "Starting make buildworld with ${PARALLEL_JOBS} jobs"
	${MAKE_CMD} -C ${SRC_BASE} buildworld ${MAKE_JOBS} \
	    ${MAKEWORLDARGS} || err 1 "Failed to 'make buildworld'"

	installworld

	if [ ${XDEV} -eq 1 ]; then
		msg "Starting make native-xtools with ${PARALLEL_JOBS} jobs"
		${MAKE_CMD} -C /usr/src native-xtools ${MAKE_JOBS} \
		    ${MAKEWORLDARGS} NO_SHARED=y || err 1 "Failed to 'make native-xtools'"
		XDEV_TOOLS=/usr/obj/${TARGET}.${TARGET_ARCH}/nxb-bin
		rm -rf ${JAILMNT}/nxb-bin || err 1 "Failed to remove old native-xtools"
		mv ${XDEV_TOOLS} ${JAILMNT} || err 1 "Failed to move native-xtools"
		cat >> ${JAILMNT}/etc/make.conf <<- EOF
		CC=/nxb-bin/usr/bin/cc
		CPP=/nxb-bin/usr/bin/cpp
		CXX=/nxb-bin/usr/bin/c++
		AS=/nxb-bin/usr/bin/as
		NM=/nxb-bin/usr/bin/nm
		LD=/nxb-bin/usr/bin/ld
		OBJCOPY=/nxb-bin/usr/bin/objcopy
		SIZE=/nxb-bin/usr/bin/size
		STRIPBIN=/nxb-bin/usr/bin/strip
		SED=/nxb-bin/usr/bin/sed
		READELF=/nxb-bin/usr/bin/readelf
		RANLIB=/nxb-bin/usr/bin/ranlib
		YACC=/nxb-bin/usr/bin/yacc
		NM=/nxb-bin/usr/bin/nm
		MAKE=/nxb-bin/usr/bin/make
		STRINGS=/nxb-bin/usr/bin/strings
		AWK=/nxb-bin/usr/bin/awk
		FLEX=/nxb-bin/usr/bin/flex
		_MAKE_JOBS=-j1
		EOF

		# hardlink these files to capture scripts and tools
		# that explicitly call them instead of using paths.
		HLINK_FILES="usr/bin/env usr/bin/gzip usr/bin/id \
				usr/bin/make usr/bin/dirname usr/bin/diff \
				usr/bin/find usr/bin/gzcat usr/bin/awk \
				usr/bin/touch usr/bin/sed usr/bin/patch \
				usr/bin/install usr/bin/gunzip usr/bin/sort \
				usr/bin/tar usr/bin/xargs usr/sbin/chown bin/cp \
				bin/cat bin/chmod bin/echo bin/expr \
				bin/hostname bin/ln bin/ls bin/mkdir bin/mv \
				bin/realpath bin/rm bin/rmdir bin/sleep \
				sbin/sha256 sbin/sha512 sbin/md5 sbin/sha1"

		# Endian issues on mips/mips64 are not handling exec of 64bit shells
		# from emulated environments correctly.  This works just fine on ARM
		# because of the same issue, so allow it for now.
		[ ${TARGET} = "mips" ] || \
		    HLINK_FILES="${HLINK_FILES} bin/sh bin/csh"

		for file in ${HLINK_FILES}; do
			if [ -f "${JAILMNT}/nxb-bin/${file}" ]; then
				rm -f ${JAILMNT}/${file}
				ln ${JAILMNT}/nxb-bin/${file} ${JAILMNT}/${file}
			fi
		done
	fi
}

install_from_src() {
	local cpignore_flag cpignore

	export TARGET=${ARCH%.*}
	export TARGET_ARCH=${ARCH#*.}

	msg_n "Copying ${SRC_BASE} to ${JAILMNT}/usr/src..."
	mkdir -p ${JAILMNT}/usr/src
	if [ -f ${SRC_BASE}/usr/src/.cpignore ]; then
		cpignore_flag="-x"
	else
		cpignore=$(mktemp -t cpignore)
		cpignore_flag="-X ${cpignore}"
		# Ignore some files
		cat > ${cpignore} <<-EOF
		.git
		.svn
		EOF
	fi
	cpdup -i0 ${cpignore_flag} ${SRC_BASE} ${JAILMNT}/usr/src
	[ -n "${cpignore}" ] && rm -f ${cpignore}
	echo " done"

	setup_compat_env
	installworld
}

install_from_svn() {
	local var_version_extra="$1"
	local UPDATE=0
	local proto
	local svn_rev

	if [ -d "${SRC_BASE}" ]; then
		UPDATE=1
	else
		mkdir -p ${SRC_BASE}
	fi
	case ${METHOD} in
	svn+http) proto="http" ;;
	svn+https) proto="https" ;;
	svn+ssh) proto="svn+ssh" ;;
	svn+file) proto="file" ;;
	svn) proto="svn" ;;
	esac
	if [ ${UPDATE} -eq 0 ]; then
		msg_n "Checking out the sources from svn..."
		${SVN_CMD} -q co ${proto}://${SVN_HOST}/base/${VERSION} ${SRC_BASE} || err 1 " fail"
		echo " done"
		if [ -n "${SRCPATCHFILE}" ]; then
			msg_n "Patching the sources with ${SRCPATCHFILE}"
			${SVN_CMD} -q patch ${SRCPATCHFILE} ${SRC_BASE} || err 1 " fail"
			echo done
		fi
	else
		msg_n "Updating the sources from svn..."
		${SVN_CMD} upgrade ${SRC_BASE} 2>/dev/null || :
		${SVN_CMD} -q update -r ${TORELEASE:-head} ${SRC_BASE} || err 1 " fail"
		echo " done"
	fi
	build_and_install_world

	svn_rev=$(${SVN_CMD} info ${SRC_BASE} |
	    awk '/Last Changed Rev:/ {print $4}')
	setvar "${var_version_extra}" "r${svn_rev}"
}

install_from_csup() {
	local var_version_extra="$1"
	local UPDATE=0
	[ -d "${SRC_BASE}" ] && UPDATE=1
	mkdir -p ${JAILMNT}/etc
	mkdir -p ${JAILMNT}/var/db
	mkdir -p ${JAILMNT}/usr
	[ -z ${CSUP_HOST} ] && err 2 "CSUP_HOST has to be defined in the configuration to use csup"
	if [ "${UPDATE}" -eq 0 ]; then
		echo "*default base=${JAILMNT}/var/db
*default prefix=${JAILMNT}/usr
*default release=cvs tag=${VERSION}
*default delete use-rel-suffix
src-all" > ${JAILMNT}/etc/supfile
	fi
	csup -z -h ${CSUP_HOST} ${JAILMNT}/etc/supfile || err 1 "Fail to fetch sources"
	build_and_install_world
}

install_from_ftp() {
	local var_version_extra="$1"
	mkdir ${JAILMNT}/fromftp
	local URL V

	V=${ALLBSDVER:-${VERSION}}
	case $V in
	[0-4].*) HASH=MD5 ;;
	5.[0-4]*) HASH=MD5 ;;
	*) HASH=SHA256 ;;
	esac

	DISTS="${DISTS} base games"
	[ -z "${SRCPATH}" ] && DISTS="${DISTS} src"
	DISTS="${DISTS} ${EXTRA_DISTS}"

	if [ ${V%%.*} -lt 9 ]; then
		msg "Fetching sets for FreeBSD ${V} ${ARCH}"
		case ${METHOD} in
		ftp|http|gjb)
			case ${VERSION} in
				*-PRERELEASE|*-STABLE) type=snapshots ;;
				*) type=releases ;;
			esac

			# Check that the defaults have been changed
			echo ${FREEBSD_HOST} | egrep -E "(_PROTO_|_CHANGE_THIS_)" > /dev/null
			if [ $? -eq 0 ]; then
				msg "FREEBSD_HOST from config invalid; defaulting to http://ftp.freebsd.org"
				FREEBSD_HOST="http://ftp.freebsd.org"
			fi
			URL="${FREEBSD_HOST}/pub/FreeBSD/${type}/${ARCH}/${V}" ;;
		url=*) URL=${METHOD##url=} ;;
		allbsd) URL="https://pub.allbsd.org/FreeBSD-snapshots/${ARCH}-${ARCH}/${V}-JPSNAP/ftp" ;;
		ftp-archive) URL="ftp://ftp-archive.freebsd.org/pub/FreeBSD-Archive/old-releases/${ARCH}/${V}" ;;
		esac
		DISTS="${DISTS} dict"
		[ "${NO_LIB32:-no}" = "no" -a "${ARCH}" = "amd64" ] &&
			DISTS="${DISTS} lib32"
		for dist in ${DISTS}; do
			fetch_file ${JAILMNT}/fromftp/ ${URL}/$dist/CHECKSUM.${HASH} ||
				err 1 "Fail to fetch checksum file"
			sed -n "s/.*(\(.*\...\)).*/\1/p" \
				${JAILMNT}/fromftp/CHECKSUM.${HASH} | \
				while read pkg; do
				[ ${pkg} = "install.sh" ] && continue
				# Let's retry at least one time
				fetch_file ${JAILMNT}/fromftp/ ${URL}/${dist}/${pkg}
			done
		done

		msg "Extracting sets:"
		for SETS in ${JAILMNT}/fromftp/*.aa; do
			SET=`basename $SETS .aa`
			echo -e "\t- $SET...\c"
			case ${SET} in
				s*)
					APPEND="usr/src"
					;;
				*)
					APPEND=""
					;;
			esac
			(cat ${JAILMNT}/fromftp/${SET}.* || echo Error) | \
				tar --unlink -xpf - -C ${JAILMNT}/${APPEND} || err 1 " fail"
			echo " done"
		done
	else
		local type
		case ${METHOD} in
			ftp|http|gjb)
				case ${VERSION} in
					*-CURRENT|*-PRERELEASE|*-STABLE) type=snapshots ;;
					*) type=releases ;;
				esac

				# Check that the defaults have been changed
				echo ${FREEBSD_HOST} | egrep -E "(_PROTO_|_CHANGE_THIS_)" > /dev/null
				if [ $? -eq 0 ]; then
					msg "FREEBSD_HOST from config invalid; defaulting to http://ftp.freebsd.org"
					FREEBSD_HOST="http://ftp.freebsd.org"
				fi

				URL="${FREEBSD_HOST}/pub/FreeBSD/${type}/${ARCH}/${ARCH}/${V}"
				;;
			allbsd) URL="https://pub.allbsd.org/FreeBSD-snapshots/${ARCH}-${ARCH}/${V}-JPSNAP/ftp" ;;
			ftp-archive) URL="ftp://ftp-archive.freebsd.org/pub/FreeBSD-Archive/old-releases/${ARCH}/${V}" ;;
			url=*) URL=${METHOD##url=} ;;
		esac

		# Games check - Removed from HEAD in r278616
		DISTS="${DISTS} lib32"
		fetch_file ${JAILMNT}/fromftp/MANIFEST ${URL}/MANIFEST
		for dist in ${DISTS}; do
			grep -q ${dist} ${JAILMNT}/fromftp/MANIFEST || continue
			msg "Fetching ${dist} for FreeBSD ${V} ${ARCH}"
			fetch_file ${JAILMNT}/fromftp/${dist}.txz ${URL}/${dist}.txz
			msg_n "Extracting ${dist}..."
			tar -xpf ${JAILMNT}/fromftp/${dist}.txz -C  ${JAILMNT}/ || err 1 " fail"
			echo " done"
		done
	fi

	msg_n "Cleaning up..."
	rm -rf ${JAILMNT}/fromftp/
	echo " done"
}

install_from_tar() {
	msg_n "Installing ${VERSION} ${ARCH} from ${TARBALL} ..."
	tar -xpf ${TARBALL} -C ${JAILMNT}/ || err 1 " fail"
	echo " done"
}

create_jail() {
	[ "${JAILNAME#*.*}" = "${JAILNAME}" ] ||
		err 1 "The jailname cannot contain a period (.). See jail(8)"

	if [ "${METHOD}" = "null" ]; then
		[ -z "${JAILMNT}" ] && \
		    err 1 "Must set -M to path of jail to use"
		[ "${JAILMNT}" = "/" ] && \
		    err 1 "Cannot use /"
	fi

	if [ -z ${JAILMNT} ]; then
		[ -z ${BASEFS} ] && err 1 "Please provide a BASEFS variable in your poudriere.conf"
		JAILMNT=${BASEFS}/jails/${JAILNAME}
	fi

	if [ -z "${JAILFS}" -a -z "${NO_ZFS}" ]; then
		[ -z ${ZPOOL} ] && err 1 "Please provide a ZPOOL variable in your poudriere.conf"
		JAILFS=${ZPOOL}${ZROOTFS}/jails/${JAILNAME}
	fi

	SRC_BASE="${JAILMNT}/usr/src"

	case ${METHOD} in
	ftp|http|gjb|ftp-archive|url=*)
		FCT=install_from_ftp
		;;
	allbsd)
		FCT=install_from_ftp
		ALLBSDVER=`fetch -qo - \
			https://pub.allbsd.org/FreeBSD-snapshots/${ARCH}-${ARCH}/ | \
			sed -n "s,.*href=\"\(.*${VERSION}.*\)-JPSNAP/\".*,\1,p" | \
			sort -k 3 -t - -r | head -n 1 `
		[ -z ${ALLBSDVER} ] && err 1 "Unknown version $VERSION"

		OIFS=${IFS}
		IFS=-
		set -- ${ALLBSDVER}
		IFS=${OIFS}
		RELEASE="${ALLBSDVER}-JPSNAP/ftp"
		;;
	svn*)
		test -x "${SVN_CMD}" || err 1 "svn or svnlite not installed. Perhaps you need to 'pkg install subversion'"
		case ${VERSION} in
			stable/*![0-9]*)
				err 1 "bad version number for stable version"
				;;
			head@*![0-9]*)
				err 1 "bad revision number for head version"
				;;
			release/*![0-9]*.[0-9].[0-9])
				err 1 "bad version number for release version"
				;;
			releng/*![0-9]*.[0-9])
				err 1 "bad version number for releng version"
				;;
			stable/*|head*|release/*|releng/*.[0-9]|projects/*) ;;
			*)
				err 1 "version with svn should be: head[@rev], stable/N, release/N, releng/N or projects/X"
				;;
		esac
		FCT=install_from_svn
		;;
	csup)
		case ${VERSION} in
			.)
				;;
			RELENG_*![0-9]*_[0-9])
				err 1 "bad version number for RELENG"
				;;
			RELENG_*![0-9]*)
				err 1 "bad version number for RELENG"
				;;
			RELENG_*|.) ;;
			*)
				err 1 "version with csup should be: . or RELENG_N or RELEASE_N"
				;;
		esac
		msg "csup has been depreciated by FreeBSD. Only use if you are syncing with your own csup repo."
		FCT=install_from_csup
		;;
	src=*)
		SRC_BASE="${METHOD#src=}"
		FCT=install_from_src
		;;
	tar=*)
		FCT=install_from_tar
		TARBALL="${METHOD##*=}"
		[ -z "${TARBALL}" ] && \
		    err 1 "Must use format -m tar=/path/to/tarball.tar"
		[ -r "${TARBALL}" ] || err 1 "Cannot read file ${TARBALL}"
		METHOD="${METHOD%%=*}"
		;;
	null)
		JAILFS=none
		FCT=
		;;
	*)
		err 2 "Unknown method to create the jail"
		;;
	esac

	createfs ${JAILNAME} ${JAILMNT} ${JAILFS:-none}
	[ -n "${JAILFS}" -a "${JAILFS}" != "none" ] && jset ${JAILNAME} fs ${JAILFS}
	jset ${JAILNAME} version ${VERSION}
	jset ${JAILNAME} timestamp $(date +%s)
	jset ${JAILNAME} arch ${ARCH}
	jset ${JAILNAME} mnt ${JAILMNT}
	[ -n "$SRCPATH" ] && jset ${JAILNAME} srcpath ${SRCPATH}

	# Wrap the jail creation in a special cleanup hook that will remove the jail
	# if any error is encountered
	CLEANUP_HOOK=cleanup_new_jail
	jset ${JAILNAME} method ${METHOD}
	[ -n "${FCT}" ] && ${FCT} version_extra

	if [ -r "${SRC_BASE}/sys/conf/newvers.sh" ]; then
		RELEASE=$(update_version "${version_extra}")
	else
		RELEASE="${VERSION}"
	fi

	cp -f "${JAILMNT}/etc/login.conf" "${JAILMNT}/etc/login.conf.orig"
	update_version_env "${RELEASE}"

	pwd_mkdb -d ${JAILMNT}/etc/ -p ${JAILMNT}/etc/master.passwd

	markfs clean ${JAILMNT}

	# Always update when using FreeBSD dists
	case ${METHOD} in
		ftp|http|ftp-archive)
			update_jail
			;;
	esac

	unset CLEANUP_HOOK

	msg "Jail ${JAILNAME} ${VERSION} ${ARCH} is ready to be used"
}

info_jail() {
	local nbb nbf nbi nbq nbs tobuild
	local building_started status log
	local elapsed elapsed_days elapsed_hms elapsed_timestamp
	local now start_time timestamp
	local jversion jarch jmethod pmethod mnt fs

	jail_exists ${JAILNAME} || err 1 "No such jail: ${JAILNAME}"

	POUDRIERE_BUILD_TYPE=bulk
	BUILDNAME=latest

	_log_path log
	now=$(date +%s)

	_bget status status 2>/dev/null || :
	_bget nbq stats_queued 2>/dev/null || nbq=0
	_bget nbb stats_built 2>/dev/null || nbb=0
	_bget nbf stats_failed 2>/dev/null || nbf=0
	_bget nbi stats_ignored 2>/dev/null || nbi=0
	_bget nbs stats_skipped 2>/dev/null || nbs=0
	tobuild=$((nbq - nbb - nbf - nbi - nbs))

	_jget jversion ${JAILNAME} version
	_jget jarch ${JAILNAME} arch
	_jget jmethod ${JAILNAME} method
	_jget timestamp ${JAILNAME} timestamp 2>/dev/null || :
	_jget mnt ${JAILNAME} mnt 2>/dev/null || :
	_jget fs ${JAILNAME} fs 2>/dev/null || fs=""

	echo "Jail name:         ${JAILNAME}"
	echo "Jail version:      ${jversion}"
	echo "Jail arch:         ${jarch}"
	echo "Jail method:       ${jmethod}"
	echo "Jail mount:        ${mnt}"
	echo "Jail fs:           ${fs}"
	if [ -n "${timestamp}" ]; then
		echo "Jail updated:      $(date -j -r ${timestamp} "+%Y-%m-%d %H:%M:%S")"
	fi
	if porttree_exists ${PTNAME}; then
		_pget pmethod ${PTNAME} method
		echo "Tree name:         ${PTNAME}"
		echo "Tree method:       ${pmethod:--}"
#		echo "Tree updated:      $(pget ${PTNAME} timestamp)"
		echo "Status:            ${status}"
		if calculate_elapsed_from_log ${now} ${log}; then
			start_time=${_start_time}
			elapsed=${_elapsed_time}
			building_started=$(date -j -r ${start_time} "+%Y-%m-%d %H:%M:%S")
			elapsed_days=$((elapsed/86400))
			calculate_duration elapsed_hms "${elapsed}"
			case ${elapsed_days} in
				0) elapsed_timestamp="${elapsed_hms}" ;;
				1) elapsed_timestamp="1 day, ${elapsed_hms}" ;;
				*) elapsed_timestamp="${elapsed_days} days, ${elapsed_hms}" ;;
			esac
			echo "Building started:  ${building_started}"
			echo "Elapsed time:      ${elapsed_timestamp}"
			echo "Packages built:    ${nbb}"
			echo "Packages failed:   ${nbf}"
			echo "Packages ignored:  ${nbi}"
			echo "Packages skipped:  ${nbs}"
			echo "Packages total:    ${nbq}"
			echo "Packages left:     ${tobuild}"
		fi
	fi

	unset POUDRIERE_BUILD_TYPE
}

check_emulation() {
	if need_emulation "${ARCH}"; then
		msg "Cross-building ports for ${ARCH} on ${REALARCH} requires QEMU"
		[ -x "${BINMISC}" ] || \
		    err 1 "Cannot find ${BINMISC}. Install ${BINMISC} and restart"
		EMULATOR=$(${BINMISC} lookup ${ARCH#*.} 2>/dev/null | awk '/interpreter:/ {print $2}')
		[ -x "${EMULATOR}" ] || \
		    err 1 "You need to setup an emulator with binmiscctl(8) for ${ARCH#*.}"
	fi
}

. ${SCRIPTPREFIX}/common.sh

get_host_arch ARCH
REALARCH=${ARCH}
START=0
STOP=0
LIST=0
DELETE=0
CREATE=0
RENAME=0
QUIET=0
NAMEONLY=0
INFO=0
UPDATE=0
PTNAME=default
SETNAME=""
BINMISC="/usr/sbin/binmiscctl"
XDEV=0

while getopts "iJ:j:v:a:z:m:nf:M:sdklqcip:r:ut:z:P:S:x" FLAG; do
	case "${FLAG}" in
		i)
			INFO=1
			;;
		j)
			JAILNAME=${OPTARG}
			;;
		J)
			PARALLEL_JOBS=${OPTARG}
			;;
		v)
			VERSION=${OPTARG}
			;;
		a)
			ARCH=${OPTARG}
			# If TARGET=TARGET_ARCH trim it away and just use
			# TARGET_ARCH
			[ "${ARCH%.*}" = "${ARCH#*.}" ] && ARCH="${ARCH#*.}"
			;;
		m)
			METHOD=${OPTARG}
			;;
		n)
			NAMEONLY=1
			;;
		f)
			JAILFS=${OPTARG}
			;;
		M)
			JAILMNT=${OPTARG}
			;;
		s)
			START=1
			;;
		k)
			STOP=1
			;;
		l)
			LIST=1
			;;
		c)
			CREATE=1
			;;
		d)
			DELETE=1
			;;
		p)
			PTNAME=${OPTARG}
			;;
		P)
			[ -f ${OPTARG} ] || err 1 "No such patch"
			# If this is a relative path, add in ${PWD} as
			# a cd / was done.
			[ "${OPTARG#/}" = "${OPTARG}" ] && \
			    OPTARG="${SAVED_PWD}/${OPTARG}"
			SRCPATCHFILE="${OPTARG}"
			;;
		S)
			[ -d ${OPTARG} ] || err 1 "No such directory ${OPTARG}"
			SRCPATH=${OPTARG}
			;;
		q)
			QUIET=1
			;;
		u)
			UPDATE=1
			;;
		r)
			RENAME=1;
			NEWJAILNAME=${OPTARG}
			;;
		t)
			TORELEASE=${OPTARG}
			;;
		x)
			XDEV=1
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

METHOD=${METHOD:-ftp}
if [ -n "${JAILNAME}" -a ${CREATE} -eq 0 ]; then
	_jget ARCH ${JAILNAME} arch 2>/dev/null || :
	_jget JAILFS ${JAILNAME} fs 2>/dev/null || :
	_jget JAILMNT ${JAILNAME} mnt 2>/dev/null || :
fi

case "${CREATE}${INFO}${LIST}${STOP}${START}${DELETE}${UPDATE}${RENAME}" in
	10000000)
		test -z ${JAILNAME} && usage JAILNAME
		test -z ${VERSION} && usage VERSION
		jail_exists ${JAILNAME} && \
		    err 2 "The jail ${JAILNAME} already exists"
		check_emulation
		maybe_run_queued "${saved_argv}"
		create_jail
		;;
	01000000)
		test -z ${JAILNAME} && usage JAILNAME
		export MASTERNAME=${JAILNAME}-${PTNAME}${SETNAME:+-${SETNAME}}
		_mastermnt MASTERMNT
		export MASTERMNT
		info_jail
		;;
	00100000)
		list_jail
		;;
	00010000)
		test -z ${JAILNAME} && usage JAILNAME
		porttree_exists ${PTNAME} || err 2 "No such ports tree ${PTNAME}"
		maybe_run_queued "${saved_argv}"
		export MASTERNAME=${JAILNAME}-${PTNAME}${SETNAME:+-${SETNAME}}
		_mastermnt MASTERMNT
		export MASTERMNT
		jail_runs ${MASTERNAME} ||
		    msg "Jail ${MASTERNAME} not running, but cleaning up anyway"
		jail_stop
		;;
	00001000)
		export SET_STATUS_ON_START=0
		test -z ${JAILNAME} && usage JAILNAME
		porttree_exists ${PTNAME} || err 2 "No such ports tree ${PTNAME}"
		maybe_run_queued "${saved_argv}"
		export MASTERNAME=${JAILNAME}-${PTNAME}${SETNAME:+-${SETNAME}}
		_mastermnt MASTERMNT
		export MASTERMNT
		jail_start ${JAILNAME} ${PTNAME} ${SETNAME}
		JNETNAME="n"
		;;
	00000100)
		test -z ${JAILNAME} && usage JAILNAME
		maybe_run_queued "${saved_argv}"
		delete_jail
		;;
	00000010)
		test -z ${JAILNAME} && usage JAILNAME
		jail_exists ${JAILNAME} || err 1 "No such jail: ${JAILNAME}"
		maybe_run_queued "${saved_argv}"
		jail_runs ${JAILNAME} && \
		    err 1 "Unable to update jail ${JAILNAME}: it is running"
		check_emulation
		update_jail
		;;
	00000001)
		test -z ${JAILNAME} && usage JAILNAME
		maybe_run_queued "${saved_argv}"
		rename_jail
		;;
	*)
		usage
		;;
esac
