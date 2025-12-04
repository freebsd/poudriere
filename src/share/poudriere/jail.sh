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

. ${SCRIPTPREFIX}/common.sh

METHOD_DEF=http

usage() {
	if [ $# -gt 0 ]; then
		echo "Missing: $*" >&2
	fi
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
    -b            -- Build the OS (for use with -m src)
    -B            -- Build the pkgbase set (for use with -b or -m git/svn/...)
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
    -K kernel     -- Build the jail with the kernel
    -M mountpoint -- Mountpoint
    -m method     -- When used with -c, overrides the default method for
                     obtaining and building the jail. See poudriere(8) for more
                     details. Can be one of:
                       'ftp-archive', 'ftp', 'freebsdci', 'http', 'null',
		       'src=PATH', 'tar=PATH', 'url=URL', 'pkgbase[=repo]' or
		       '{git,svn}{,+http,+https,+file,+ssh}' (e.g., 'git+https').
                     The default is '${METHOD_DEF}'.
    -P patch      -- Specify a patch to apply to the source before building.
    -S srcpath    -- Specify a path to the source tree to be used.
    -D            -- Do a full git clone without --depth (default: --depth=1)
    -t version    -- Version of FreeBSD to upgrade the jail to.
    -U url        -- Specify a url to fetch the sources (with method git, svn and pkgbase).
    -X            -- Do not build and setup native-xtools cross compile tools in jail
                     when building for a different TARGET ARCH than the host.
                     Only applies if TARGET_ARCH and HOST_ARCH are different.

Options for -d:
    -C clean      -- Clean remaining data existing in poudriere data directory.
                     See poudriere(8) for more details. Can be one of:
                       all, cache, logs, packages, wrkdirs
    -y            -- Do not prompt for confirmation when deleting a jail.

Options for -s and -k:
    -p tree       -- Specify which ports tree to start/stop the jail with.
    -z set        -- Specify which SET the jail to start/stop with.
EOF
	exit ${EX_USAGE}
}

list_jail() {
	local format
	local j name version arch method mnt timestamp time jails osversion

	if [ ${NAMEONLY} -eq 0 ]; then
		format='%%-%ds %%-%ds %%-%ds %%-%ds %%-%ds %%-%ds %%-%ds'
		display_setup "${format}" "-d -k2,2V -k4,4 -k1,1"
		display_add "JAILNAME" "VERSION" "OSVERSION" "ARCH" "METHOD" \
		    "TIMESTAMP" "PATH"
	else
		format='%s'
		display_setup "${format}" "-d"
		display_add JAILNAME
	fi
	[ -d ${POUDRIERED}/jails ] || return 0
	jails="$(find "${POUDRIERED:?}/jails" -type d \
	    -maxdepth 1 -mindepth 1 -print)"
	for j in ${jails}; do
		name=${j##*/}
		if [ ${NAMEONLY} -eq 0 ]; then
			_jget version ${name} version
			_jget version_vcs ${name} version_vcs || \
			    version_vcs=
			_jget arch ${name} arch
			_jget method ${name} method
			_jget mnt ${name} mnt
			_jget timestamp ${name} timestamp || :
			if [ -r "${mnt}/usr/include/sys/param.h" ]; then
				osversion=$(awk '/^\#define[[:blank:]]__FreeBSD_version/ {print $3}' "${mnt}/usr/include/sys/param.h")
			else
				osversion=
			fi
			time=
			if [ -n "${timestamp}" ]; then
				time="$(date -j -r ${timestamp} "+%Y-%m-%d %H:%M:%S")"
			fi
			if [ -n "${version_vcs}" ]; then
				version="${version} ${version_vcs}"
			fi
			display_add "${name}" "${version}" "${osversion}" \
			    "${arch}" \
			    "${method}" "${time}" "${mnt}"
		else
			display_add ${name}
		fi
	done
	if [ ${QUIET} -eq 1 ]; then
		quiet="-q"
	fi
	display_output ${quiet}
}

delete_jail() {
	local cache_dir method
	local cleandir depth

	if [ -z "${JAILNAME}" ]; then
		usage JAILNAME
	fi
	jail_exists ${JAILNAME} || err 1 "No such jail: ${JAILNAME}"
	if jail_runs ${JAILNAME}; then
		err 1 "Unable to delete jail ${JAILNAME}: it is running"
	fi
	msg_n "Removing ${JAILNAME} jail..."
	method=$(jget ${JAILNAME} method)
	if [ "${method}" = "null" ]; then
		# Legacy jail cleanup. New jails don't create this file.
		if [ -f "${JAILMNT:?}/etc/login.conf.orig" ]; then
			mv -f ${JAILMNT:?}/etc/login.conf.orig \
			    ${JAILMNT:?}/etc/login.conf
			cap_mkdb ${JAILMNT:?}/etc/login.conf
		fi
	elif [ -n "${JAILMNT:+set}" ]; then
		TMPFS_ALL=0 destroyfs ${JAILMNT:?} jail || :
	fi
	cache_dir="${POUDRIERE_DATA}/cache/${JAILNAME}-*"
	rm -rfx ${POUDRIERED:?}/jails/${JAILNAME} ${cache_dir} \
		${POUDRIERE_DATA:?}/.m/${JAILNAME}-* || :
	echo " done"
	if [ "${CLEANJAIL}" = "none" ]; then
		return 0
	fi
	msg_n "Cleaning ${JAILNAME} data..."
	case ${CLEANJAIL} in
		all) cleandir="${POUDRIERE_DATA}" ;;
		cache) cleandir="${POUDRIERE_DATA}/cache"; depth=1 ;;
		logs) cleandir="${POUDRIERE_DATA}/logs"; depth=5 ;;
		packages) cleandir="${POUDRIERE_DATA}/packages"; depth=1 ;;
		wrkdirs) cleandir="${POUDRIERE_DATA}/wkdirs"; depth=1 ;;
	esac
	if [ -n "${cleandir}" ]; then
		find -x "${cleandir:?}/" -name "${JAILNAME}-*" \
		    ${depth:+-maxdepth ${depth}} -print0 | \
		    xargs -0 rm -rfx || :
	fi
	echo " done"
}

cleanup_new_jail() {
	msg "Error while creating jail, cleaning up." >&2
	delete_jail
}

# Lookup new version from newvers and set in jset version
update_version() {
	local version_extra="$1"

	if [ -r "${SRC_BASE}/sys/conf/newvers.sh" ]; then
		eval `egrep "^REVISION=|^BRANCH=" ${SRC_BASE}/sys/conf/newvers.sh `
		RELEASE=${REVISION}-${BRANCH}
	else
		RELEASE=$(jget ${JAILNAME} version)
	fi
	[ -n "${RELEASE}" ] || err 1 "updated_version: Failed to determine RELEASE"
	if [ -n "${version_extra}" ]; then
		RELEASE="${RELEASE} ${version_extra}"
	fi
	jset ${JAILNAME} version "${RELEASE}"
	echo "${RELEASE}"
}

rename_jail() {
	local cache_dir

	jail_exists ${JAILNAME} || err 1 "No such jail: ${JAILNAME}"
	msg_n "Renaming '${JAILNAME}' in '${NEWJAILNAME}'"
	mv ${POUDRIERED:?}/jails/${JAILNAME} ${POUDRIERED:?}/jails/${NEWJAILNAME}
	cache_dir="${POUDRIERE_DATA:?}/cache/${JAILNAME}-*"
	rm -rf ${cache_dir:?} >/dev/null 2>&1 || :
	echo " done"
	msg_warn "The packages, logs and filesystems have not been renamed."
	msg_warn "If you choose to rename the filesystem then modify the 'mnt' and 'fs' files in ${POUDRIERED}/jails/${NEWJAILNAME}"
}

update_pkgbase() {
	local make_jobs
	local destdir="${JAILMNT}"

	if [ ${JAIL_OSVERSION} -gt 1100086 ]; then
		make_jobs="${MAKE_JOBS}"
	fi

	msg "Starting make update-packages"
	env ${PKG_REPO_SIGNING_KEY:+PKG_REPO_SIGNING_KEY="${PKG_REPO_SIGNING_KEY}"} IGNORE_OSMAJOR=y \
		${MAKE_CMD} -C "${SRC_BASE}" ${make_jobs} update-packages \
			KERNCONF="${KERNEL}" DESTDIR="${destdir:?}" \
			REPODIR="${POUDRIERE_DATA}/images/${JAILNAME}-repo" \
			NO_INSTALLEXTRAKERNELS=no ${MAKEWORLDARGS}
	case $? in
	    0)
		run_hook jail pkgbase "${POUDRIERE_DATA}/images/${JAILNAME}-repo"
		return
		;;
	    2)
		env ${PKG_REPO_SIGNING_KEY:+PKG_REPO_SIGNING_KEY="${PKG_REPO_SIGNING_KEY}"} \
			${MAKE_CMD} -C "${SRC_BASE}" ${make_jobs} packages \
				KERNCONF="${KERNEL}" DESTDIR="${destdir:?}" \
				REPODIR="${POUDRIERE_DATA}/images/${JAILNAME}-repo" \
				NO_INSTALLEXTRAKERNELS=no ${MAKEWORLDARGS} || \
			err 1 "Failed to 'make packages'"
		run_hook jail pkgbase "${POUDRIERE_DATA}/images/${JAILNAME}-repo"
		;;
	    *)
		err 1 "Failed to 'make update-packages'"
		;;
	esac
}

update_jail() {
	local pkgbase

	METHOD=$(jget ${JAILNAME} method)
	: ${SRCPATH:=$(jget ${JAILNAME} srcpath || echo)}
	if [ "${METHOD}" = "null" -a -n "${SRCPATH}" ]; then
		SRC_BASE="${SRCPATH}"
	else
		SRC_BASE="${JAILMNT}/usr/src"
	fi
	if [ -z "${METHOD}" -o "${METHOD}" = "-" ]; then
		METHOD="${METHOD_DEF}"
		jset ${JAILNAME} method ${METHOD}
	fi
	msg "Upgrading using ${METHOD}"
	: ${KERNEL:=$(jget ${JAILNAME} kernel || echo)}
	case ${METHOD} in
	ftp|http|ftp-archive)
		local FREEBSD_UPDATE fu_bin fu_basedir fu_bdhash fu_workdir version

		# In case we use FreeBSD dists and TORELEASE is present, check if it's a release branch.
		if [ -n "${TORELEASE}" ]; then
		  case ${TORELEASE} in
		    *-ALPHA*|*-CURRENT|*-PRERELEASE|*-STABLE)
			msg_error "Only release branches are supported by the ${METHOD} method."
			msg_error "Please try to upgrade to a new BETA, RC or RELEASE version."
			exit 1
			;;
		    *) ;;
		  esac
		fi
		# Avoid conflict with modified login.conf before we stopped
		# modifying it in commit bcda4cf990d.
		sed -i '' \
		    -e 's#:\(setenv.*\),UNAME_r=.*UNAME_v=FreeBSD.*,OSVERSION=[^:,]*\([,:]\)#:\1\2#' \
		    -e 's#:\(setenv.*\),ABI_FILE=/usr/lib/crt1.o[^:,]*\([,:]\)#:\1\2#' \
		    -e 's#:\(setenv.*\),UNAME_m=.*,UNAME_p=[^:,]*\([,:]\)#:\1\2#' \
		    "${JAILMNT}/etc/login.conf"
		cap_mkdb "${JAILMNT}/etc/login.conf"
		# Fix freebsd-update to not check for TTY and to allow
		# EOL branches to still get updates.
		fu_bin="$(mktemp -t freebsd-update)"
		sed \
		    -e 's/! -t 0/1 -eq 0/' \
		    -e 's/-t 0/1 -eq 1/' \
		    -e 's,\(fetch_warn_eol ||\) return 1,\1 :,' \
		    -e 's,sysctl -n kern.bootfile,echo /boot/kernel/kernel,' \
		    -e 's,service sshd restart,#service sshd restart,' \
		    /usr/sbin/freebsd-update > "${fu_bin}"
		FREEBSD_UPDATE="env PAGER=/bin/cat"
		FREEBSD_UPDATE="${FREEBSD_UPDATE} /bin/sh ${fu_bin}"
		fu_basedir="${JAILMNT}"
		fu_bdhash="$(echo "${fu_basedir}" | sha256 -q)"
		FREEBSD_UPDATE="${FREEBSD_UPDATE} -b ${fu_basedir}"
		fu_workdir="${JAILMNT}/var/db/freebsd-update"
		FREEBSD_UPDATE="${FREEBSD_UPDATE} -d ${fu_workdir}"
		_jget version ${JAILNAME} version || \
			err 1 "Missing version metadata for jail"
		FREEBSD_UPDATE="${FREEBSD_UPDATE} --currently-running ${version}"
		FREEBSD_UPDATE="${FREEBSD_UPDATE} -f ${JAILMNT}/etc/freebsd-update.conf"

		export_cross_env "${JAILNAME}" "${ARCH}" "${version}"
		if [ -z "${TORELEASE}" ]; then
			# New updates are identified by a symlink containing
			# the basedir hash and -install as suffix.  If we
			# really have new updates to install, then install them.
			if ${FREEBSD_UPDATE} fetch && \
			    [ -L "${fu_workdir}/${fu_bdhash}-install" ]; then
				yes | ${FREEBSD_UPDATE} install
			fi
		else
			# Install new kernel
			yes | ${FREEBSD_UPDATE} -r ${TORELEASE} \
			    upgrade install || err 1 "Fail to upgrade system"
			# Install new world
			yes | ${FREEBSD_UPDATE} install || \
			    err 1 "Fail to upgrade system"
			# Remove stale files
			yes | ${FREEBSD_UPDATE} install || :
			jset ${JAILNAME} version ${TORELEASE}
		fi
		unset_cross_env

		rm -f "${fu_bin:?}"
		update_version
		build_native_xtools
		cleanup_confs
		markfs clean ${JAILMNT}
		;;
	svn*|git*)
		install_from_vcs version_extra
		RELEASE=$(update_version "${version_extra}")
		make -C ${SRC_BASE} delete-old delete-old-libs DESTDIR=${JAILMNT:?} BATCH_DELETE_OLD_FILES=yes
		cleanup_confs
		markfs clean ${JAILMNT}
		;;
	src=*)
		SRC_BASE="${METHOD#src=}"
		install_from_src version_extra
		RELEASE=$(update_version "${version_extra}")
		make -C ${SRC_BASE} delete-old delete-old-libs DESTDIR=${JAILMNT:?} BATCH_DELETE_OLD_FILES=yes
		cleanup_confs
		markfs clean ${JAILMNT}
		;;
	gjb|url=*|freebsdci)
		if [ -z "${VERSION}" ]; then
			VERSION=$(jget ${JAILNAME} version)
		fi
		if [ -z "${ARCH}" ]; then
			ARCH=$(jget ${JAILNAME} arch)
		fi
		delete_jail
		create_jail
		;;
	pkgbase)
		VERSION=$(jget ${JAILNAME} version | cut -d '.' -f 1)
		[ -z "${ARCH}" ] && ARCH=$(jget ${JAILNAME} arch)
		pkg -o IGNORE_OSVERSION=yes -o ABI="FreeBSD:${VERSION}:${ARCH}" -o REPOS_DIR="${JAILMNT}/etc/pkg" -r "${JAILMNT}" update || \
			err 1 "pkg update failed"
		pkg -o IGNORE_OSVERSION=yes -o ABI="FreeBSD:${VERSION}:${ARCH}" -o REPOS_DIR="${JAILMNT}/etc/pkg" -r "${JAILMNT}" upgrade -y || \
			err 1 "pkg upgrade failed"
		markfs clean ${JAILMNT}
		;;
	csup|null|tar)
		err 1 "Upgrade is not supported with ${METHOD}; to upgrade, please delete and recreate the jail"
		;;
	*)
		err 1 "Unsupported method"
		;;
	esac
	pkgbase=$(jget ${JAILNAME} pkgbase)
	if [ -n "${pkgbase}" ] && [ "${pkgbase}" -eq 1 ]; then
		setup_src_conf "make"
		setup_src_conf "src"
		setup_src_conf "src-env"
		SETUP_CONFS=1
		export __MAKE_CONF=${JAILMNT}/etc/make.conf
		export SRCCONF=${JAILMNT}/etc/src.conf
		export SRC_ENV_CONF=${JAILMNT}/etc/src-env.conf
		update_pkgbase
		cleanup_confs
	fi
	jset ${JAILNAME} timestamp $(clock -epoch)
}

installworld() {
	local make_jobs
	local destdir="${JAILMNT}"

	if [ ${JAIL_OSVERSION} -gt 1100086 ]; then
		make_jobs="${MAKE_JOBS}"
	fi

	msg "Starting make installworld"
	${MAKE_CMD} -C "${SRC_BASE}" ${make_jobs} installworld \
	    DESTDIR=${destdir:?} DB_FROM_SRC=1 ${MAKEWORLDARGS} || \
	    err 1 "Failed to 'make installworld'"
	${MAKE_CMD} -C "${SRC_BASE}" ${make_jobs} DESTDIR=${destdir:?} \
	    DB_FROM_SRC=1 distrib-dirs ${MAKEWORLDARGS} || \
	    err 1 "Failed to 'make distrib-dirs'"
	${MAKE_CMD} -C "${SRC_BASE}" ${make_jobs} DESTDIR=${destdir:?} \
	    distribution ${MAKEWORLDARGS} || err 1 "Failed to 'make distribution'"
	if [ -n "${KERNEL}" ]; then
		msg "Starting make installkernel"
		${MAKE_CMD} -C "${SRC_BASE}" ${make_jobs} installkernel \
		    KERNCONF="${KERNEL}" NO_INSTALLEXTRAKERNELS=no DESTDIR=${destdir:?} ${MAKEWORLDARGS} || \
		    err 1 "Failed to 'make installkernel'"
	fi

	return 0
}

build_pkgbase() {
	local make_jobs
	local destdir="${JAILMNT}"

	if [ ${JAIL_OSVERSION} -gt 1100086 ]; then
		make_jobs="${MAKE_JOBS}"
	fi

	msg "Starting make packages"
	env ${PKG_REPO_SIGNING_KEY:+PKG_REPO_SIGNING_KEY="${PKG_REPO_SIGNING_KEY}"} \
		${MAKE_CMD} -C "${SRC_BASE}" ${make_jobs} packages \
			KERNCONF="${KERNEL}" DESTDIR=${destdir:?} \
			REPODIR=${POUDRIERE_DATA}/images/${JAILNAME}-repo \
			NO_INSTALLEXTRAKERNELS=no ${MAKEWORLDARGS} || \
		err 1 "Failed to 'make packages'"

	run_hook jail pkgbase "${POUDRIERE_DATA}/images/${JAILNAME}-repo"
}

setup_build_env() {
	local hostver

	if [ -n "${MAKE_CMD}" ];then
		return 0
	fi

	JAIL_OSVERSION=$(awk '/^\#define[[:blank:]]__FreeBSD_version/ {print $3}' ${SRC_BASE}/sys/sys/param.h)
	hostver=$(awk '/^\#define[[:blank:]]__FreeBSD_version/ {print $3}' /usr/include/sys/param.h)
	MAKE_CMD=make
	if [ ${hostver} -gt 1000000 -a ${JAIL_OSVERSION} -lt 1000000 ]; then
		FMAKE=$(command -v fmake 2>/dev/null)
		[ -n "${FMAKE}" ] ||
			err 1 "You need fmake installed on the host: devel/fmake"
		MAKE_CMD=${FMAKE}
	fi
	if ! [ ${VERBOSE} -gt 0 ]; then
		MAKE_CMD="${MAKE_CMD} -s"
	fi

	: ${CCACHE_BIN:="/usr/local/libexec/ccache"}
	if [ -n "${CCACHE_DIR}" -a -d ${CCACHE_BIN}/world ]; then
		export CCACHE_DIR
		if [ ${JAIL_OSVERSION} -gt 1100086 ]; then
			export WITH_CCACHE_BUILD=yes
		else
			export PATH="${CCACHE_BIN}/world:${PATH}"
		fi
		# Avoid using a ports-specific directory
		unset CCACHE_TEMPDIR
	fi

	export TARGET=${ARCH%.*}
	export TARGET_ARCH=${ARCH#*.}
	export WITH_FAST_DEPEND=yes
	MAKE_JOBS="-j${PARALLEL_JOBS}"

	mkdir -p ${JAILMNT}/etc
 	setup_src_conf "make"
	setup_src_conf "src"
	setup_src_conf "src-env"
	SETUP_CONFS=1
	if [ "${TARGET}" = "mips" ]; then
		echo "WITH_ELFTOOLCHAIN_TOOLS=y" >> ${JAILMNT}/etc/src.conf
	fi

	export __MAKE_CONF=${JAILMNT}/etc/make.conf
	export SRCCONF=${JAILMNT}/etc/src.conf
	export SRC_ENV_CONF=${JAILMNT}/etc/src-env.conf
}

# Must ensure conf files don't leak into `markfs clean`
cleanup_confs() {
	local file

	case "${SETUP_CONFS-}" in
	1) ;;
	*) return 0 ;;
	esac

	for file in /etc/make.conf /etc/src.conf /etc/src-env.conf; do
		rm -f "${JAILMNT?}/${file}"
	done
	unset SETUP_CONFS
}

setup_src_conf() {
	local src="$1"

	if [ -f "${JAILMNT:?}/etc/${src}.conf" ]; then
		rm -f "${JAILMNT:?}/etc/${src}.conf"
	fi
	touch "${JAILMNT:?}/etc/${src}.conf"
	if [ -f "${POUDRIERED:?}/${src}.conf" ]; then
		cat "${POUDRIERED:?}/${src}.conf" > "${JAILMNT}/etc/${src}.conf"
	fi
	if [ -n "${SETNAME}" ] &&
	    [ -f "${POUDRIERED:?}/${SETNAME}-${src}.conf" ]; then
		cat "${POUDRIERED:?}/${SETNAME}-${src}.conf" >> \
		    "${JAILMNT:?}/etc/${src}.conf"
	fi
	if [ -f "${POUDRIERED:?}/${JAILNAME}-${src}.conf" ]; then
		cat "${POUDRIERED:?}/${JAILNAME}-${src}.conf" >> \
		    "${JAILMNT:?}/etc/${src}.conf"
	fi
}

buildworld() {
	export SRC_BASE=${JAILMNT}/usr/src

	setup_build_env

	msg "Starting make buildworld with ${PARALLEL_JOBS} jobs"
	${MAKE_CMD} -C ${SRC_BASE} buildworld ${MAKE_JOBS} \
	    ${MAKEWORLDARGS} || err 1 "Failed to 'make buildworld'"
	BUILTWORLD=1

	if [ -n "${KERNEL}" ]; then
		msg "Starting make buildkernel with ${PARALLEL_JOBS} jobs"
		${MAKE_CMD} -C ${SRC_BASE} buildkernel ${MAKE_JOBS} \
			KERNCONF="${KERNEL}" ${MAKEWORLDARGS} || \
			err 1 "Failed to 'make buildkernel'"
	fi
}

build_native_xtools() {
	[ ${XDEV} -eq 1 ] || return 0
	[ ${BUILT_NATIVE_XTOOLS:-0} -eq 0 ] || return 0
	[ ${QEMU_EMULATING} -eq 1 ] || return 0
	setup_build_env

	# Check for which style of native-xtools to build.
	# If there is a populated NXBDIRS then it is the new style
	# fixed version with a proper sysroot.
	# Otherwise it's the older broken one, so use the host /usr/src
	# unless the user set XDEV_SRC_JAIL.
	XDEV_DIRS=$(TARGET=${TARGET} TARGET_ARCH=${TARGET_ARCH} \
	    ${MAKE_CMD} -C ${SRC_BASE} -f Makefile.inc1 -V NXBDIRS)
	if [ -n "${XDEV_DIRS}" ] || [ "${XDEV_SRC_JAIL}" = "yes" ]; then
		: ${XDEV_SRC:=${SRC_BASE}}
	else
		: ${XDEV_SRC:=/usr/src}
	fi
	# Basic sanity check
	if [ ! -f "${XDEV_SRC}/Makefile" ] || \
	    [ ! -f "${XDEV_SRC}/Makefile.inc1" ]; then
		err 1 "${XDEV_SRC} must be a working src tree to build native-xtools. Perhaps you meant to specify -X?"
	fi
	msg "Starting make native-xtools with ${PARALLEL_JOBS} jobs in ${XDEV_SRC}"
	# Can use -DNO_NXBTOOLCHAIN if we just ran buildworld to reuse the
	# toolchain already just built.
	${MAKE_CMD} -C ${XDEV_SRC} native-xtools ${MAKE_JOBS} \
	    ${BUILTWORLD:+-DNO_NXBTOOLCHAIN} \
	    ${MAKEWORLDARGS} || err 1 "Failed to 'make native-xtools' in ${XDEV_SRC}"
	rm -rf ${JAILMNT:?}/nxb-bin || err 1 "Failed to remove old native-xtools"
	# Check for native-xtools-install support
	NXTP=$(TARGET=${TARGET} TARGET_ARCH=${TARGET_ARCH} \
	    ${MAKE_CMD} -C ${XDEV_SRC} -f Makefile.inc1 -V NXTP)
	if [ -n "${NXTP}" ]; then
		# New style, we call native-xtools-install
		${MAKE_CMD} -C ${XDEV_SRC} native-xtools-install ${MAKE_JOBS} \
		    DESTDIR=${JAILMNT:?} NXTP=/nxb-bin || \
		    err 1 "Failed to 'make native-xtools-install' in ${XDEV_SRC}"
	else
		# Old style, we guess or ask where the files were dropped
		XDEV_TOOLS=$(TARGET=${TARGET} TARGET_ARCH=${TARGET_ARCH} \
		    ${MAKE_CMD} -C ${XDEV_SRC} -f Makefile.inc1 -V NXBDESTDIR)
		: ${XDEV_TOOLS:=${MAKEOBJDIRPREFIX:-/usr/obj}/${TARGET}.${TARGET_ARCH}/nxb-bin}
		mv ${XDEV_TOOLS} ${JAILMNT} || err 1 "Failed to move native-xtools"
	fi
	# The files are hard linked at bulk jail startup now.
	BUILT_NATIVE_XTOOLS=1
}

check_kernconf() {
	# Check if the kernel exists before we get too far
	if [ -n "${KERNEL}" ]; then
		KERNEL_ERR=
		for k in ${KERNEL}; do
			if [ ! -r "${SRC_BASE}/sys/${ARCH%.*}/conf/${k}" ]; then
				KERNEL_ERR="${KERNEL_ERR} ${k}"
			fi
		done
		if [ -n "${KERNEL_ERR}" ]; then
			err 1 "Unable to find specified KERNCONF:${KERNEL_ERR}"
		fi
	fi
}

install_from_src() {
	local var_version_extra="$1"
	local cpignore_flag cpignore

	msg_n "Copying ${SRC_BASE} to ${JAILMNT}/usr/src..."
	mkdir -p ${JAILMNT}/usr/src
	if [ -f ${JAILMNT}/usr/src/.cpignore ]; then
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
	do_clone -r ${cpignore_flag} "${SRC_BASE:?}" "${JAILMNT:?}/usr/src"
	if [ -n "${cpignore}" ]; then
		rm -f "${cpignore}"
	fi
	echo " done"
	check_kernconf

	if [ ${BUILD} -eq 0 ]; then
		setup_build_env
		installworld
	else
		buildworld
		installworld
		if [ ${BUILD_PKGBASE} -eq 1 ]; then
			build_pkgbase
		fi
	fi
	build_native_xtools
	# Use __FreeBSD_version as our version_extra
	setvar "${var_version_extra}" \
	    "$(awk '/^\#define[[:blank:]]__FreeBSD_version/ {print $3}' \
	    ${JAILMNT}/usr/include/sys/param.h)"
}

install_from_vcs() {
	local var_version_extra="$1"
	local UPDATE=0
	local version_vcs
	local git_sha svn_rev

	if [ -d "${SRC_BASE}" ]; then
		UPDATE=1
	else
		mkdir -p ${SRC_BASE}
	fi
	if [ ${UPDATE} -eq 0 ]; then
		case ${METHOD} in
		svn*)
			msg_n "Checking out the sources with ${METHOD}..."
			${SVN_CMD} ${quiet} checkout \
			    ${SVN_FULLURL}/${VERSION} ${SRC_BASE} || \
			    err 1 " fail"
			echo " done"
			if [ -n "${SRCPATCHFILE}" ]; then
				msg_n "Patching the sources with ${SRCPATCHFILE}"
				${SVN_CMD} ${quiet} patch ${SRCPATCHFILE} \
				    ${SRC_BASE} || err 1 " fail"
				echo done
			fi
			;;
		git*)
			# !! Any changes here should be considered for ports.sh too.
			if [ -n "${SRCPATCHFILE}" ]; then
				err 1 "Patch files not supported with git, please use feature branches"
			fi
			msg_n "Checking out the sources with ${METHOD}..."
			${GIT_CMD} clone ${GIT_DEPTH} ${quiet} \
			    ${VERSION:+-b ${VERSION}} ${GIT_FULLURL} \
			    ${SRC_BASE} || \
			    err 1 " fail"
			echo " done"
			# No support for patches, using feature branches is recommanded"
			;;
		esac
	else
		case ${METHOD} in
		svn*)
			msg_n "Updating the sources with ${METHOD}..."
			${SVN_CMD} upgrade ${SRC_BASE} 2>/dev/null || :
			${SVN_CMD} ${quiet} update -r ${TORELEASE:-head} ${SRC_BASE} || err 1 " fail"
			echo " done"
			;;
		git*)
			# !! Any changes here should be considered for ports.sh too.
			msg_n "Updating the sources with ${METHOD}..."
			${GIT_CMD} -C ${SRC_BASE} pull --rebase ${quiet} || \
			    err 1 " fail"
			if [ -n "${TORELEASE}" ]; then
				${GIT_CMD} -C ${SRC_BASE} checkout \
				    ${quiet} "${TORELEASE}" || err 1 " fail"
			fi
			echo " done"
			;;
		esac
	fi
	check_kernconf
	buildworld
	installworld
	if [ ${BUILD_PKGBASE} -eq 1 ]; then
		build_pkgbase
	fi
	build_native_xtools

	case ${METHOD} in
	svn*)
		svn_rev=$(${SVN_CMD} info ${SRC_BASE} |
		    awk '/Last Changed Rev:/ {print $4}')
		version_vcs="r${svn_rev}"
	;;
	git*)
		git_sha=$(${GIT_CMD} -C ${SRC_BASE} rev-parse --short HEAD)
		version_vcs="${git_sha}"
	;;
	esac
	jset ${JAILNAME} version_vcs "${version_vcs}"
	# Use __FreeBSD_version as our version_extra
	setvar "${var_version_extra}" \
	    "$(awk '/^\#define[[:blank:]]__FreeBSD_version/ {print $3}' \
	    ${JAILMNT}/usr/include/sys/param.h)"
}

install_from_ftp() {
	mkdir ${JAILMNT}/fromftp
	local URL V

	V=${ALLBSDVER:-${VERSION}}
	case $V in
	[0-4].*) HASH=MD5 ;;
	5.[0-4]*) HASH=MD5 ;;
	*) HASH=SHA256 ;;
	esac

	DISTS="${DISTS} base games"
	if [ -z "${SRCPATH}" -a "${NO_SRC:-no}" = "no" ]; then
		DISTS="${DISTS} src"
	fi
	DISTS="${DISTS} ${EXTRA_DISTS}"

	case "${V}" in
	[0-8][^0-9]*) # < 9
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
				msg "FREEBSD_HOST from config invalid; defaulting to https://download.FreeBSD.org"
				FREEBSD_HOST="https://download.FreeBSD.org"
			fi
			case $(echo "${FREEBSD_HOST}" | \
			    tr '[:upper:]' '[:lower:]') in
				*download.freebsd.org)
					URL="${FREEBSD_HOST}/${type}/${ARCH}/${V}"
					;;
				*)
					URL="${FREEBSD_HOST}/pub/FreeBSD/${type}/${ARCH}/${V}"
					;;
			esac
			;;
		url=*) URL=${METHOD##url=} ;;
		ftp-archive) URL="http://ftp-archive.freebsd.org/pub/FreeBSD-Archive/old-releases/${ARCH}/${V}" ;;
		freebsdci) URL="https://artifact.ci.freebsd.org/snapshot/${V}/latest_tested/${ARCH%%.*}/${ARCH##*.}" ;;
		esac
		DISTS="${DISTS} dict"
		case "${NO_LIB32:-no}.${ARCH}" in
		"no.amd64") DISTS="${DISTS} lib32" ;;
		esac
		case "${KERNEL:+set}" in
		set) DISTS="${DISTS} kernels" ;;
		esac
		for dist in ${DISTS}; do
			fetch_file ${JAILMNT}/fromftp/ "${URL}/$dist/CHECKSUM.${HASH}" ||
				err 1 "Fail to fetch checksum file"
			sed -n "s/.*(\(.*\...\)).*/\1/p" \
				${JAILMNT}/fromftp/CHECKSUM.${HASH} | \
			while read pkg; do
				case "${pkg}" in
				"install.sh") continue ;;
				esac
				# Let's retry at least one time
				fetch_file ${JAILMNT}/fromftp/ "${URL}/${dist}/${pkg}"
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
		;;
	*)
		local type
		case ${METHOD} in
			ftp|http|gjb)
				case ${VERSION} in
					*-CURRENT|*-ALPHA*|*-PRERELEASE|*-STABLE) type=snapshots ;;
					*) type=releases ;;
				esac

				# Check that the defaults have been changed
				echo ${FREEBSD_HOST} | egrep -E "(_PROTO_|_CHANGE_THIS_)" > /dev/null
				if [ $? -eq 0 ]; then
					msg "FREEBSD_HOST from config invalid; defaulting to https://download.FreeBSD.org"
					FREEBSD_HOST="https://download.FreeBSD.org"
				fi

				case $(echo "${FREEBSD_HOST}" | \
				    tr '[:upper:]' '[:lower:]') in
					*download.freebsd.org)
						URL="${FREEBSD_HOST}/${type}/${ARCH%%.*}/${ARCH##*.}/${V}"
						;;
					*)
						URL="${FREEBSD_HOST}/pub/FreeBSD/${type}/${ARCH%%.*}/${ARCH##*.}/${V}"
						;;
				esac
				;;
			ftp-archive) URL="http://ftp-archive.freebsd.org/pub/FreeBSD-Archive/old-releases/${ARCH%%.*}/${ARCH##*.}/${V}" ;;
			freebsdci) URL="https://artifact.ci.freebsd.org/snapshot/${V}/latest_tested/${ARCH%%.*}/${ARCH##*.}" ;;
			url=*) URL=${METHOD##url=} ;;
		esac

		# Copy release MANIFEST from the preinstalled set if we have it;
		# if not, download it.
		if [ -f ${SCRIPTPREFIX}/MANIFESTS/${ARCH%%.*}-${ARCH##*.}-${V} ]; then
			msg "Using pre-distributed MANIFEST for FreeBSD ${V} ${ARCH}"
			cp ${SCRIPTPREFIX}/MANIFESTS/${ARCH%%.*}-${ARCH##*.}-${V} ${JAILMNT}/fromftp/MANIFEST
		else
			msg "Fetching MANIFEST for FreeBSD ${V} ${ARCH}"
			fetch_file ${JAILMNT}/fromftp/MANIFEST ${URL}/MANIFEST
		fi

		case "${NO_LIB32:-no}" in
		"no") DISTS="${DISTS} lib32" ;;
		esac
		case "${KERNEL:+set}" in
		set) DISTS="${DISTS} kernel" ;;
		esac
		[ -s "${JAILMNT}/fromftp/MANIFEST" ] || err 1 "Empty MANIFEST file."
		for dist in ${DISTS}; do
			awk -vdist="${dist}.txz" '\
			    BEGIN {ret=1} \
			    $1 == dist {ret=0;exit} \
			    END {exit ret} \
			    ' "${JAILMNT}/fromftp/MANIFEST" || continue
			msg "Fetching ${dist} for FreeBSD ${V} ${ARCH}"
			fetch_file "${JAILMNT}/fromftp/${dist}.txz" "${URL}/${dist}.txz"
			MHASH="$(awk -vdist="${dist}.txz" '$1 == dist { print $2 }' ${JAILMNT}/fromftp/MANIFEST)"
			FHASH="$(sha256 -q ${JAILMNT}/fromftp/${dist}.txz)"
			if [ "${MHASH}" != "${FHASH}" ]; then
				err 1 "${dist}.txz checksum mismatch"
			fi
			msg_n "Extracting ${dist}..."
			tar -xpf "${JAILMNT}/fromftp/${dist}.txz" -C  ${JAILMNT}/ || err 1 " fail"
			echo " done"
		done
		;;
	esac

	msg_n "Cleaning up..."
	rm -rf ${JAILMNT:?}/fromftp/
	echo " done"

	check_kernconf
	build_native_xtools
}

install_from_tar() {
	msg_n "Installing ${VERSION} ${ARCH} from ${TARBALL} ..."
	tar -xpf ${TARBALL} -C ${JAILMNT}/ || err 1 " fail"
	echo " done"
	check_kernconf
	build_native_xtools
}

install_from_pkgbase() {
	msg_n "Installing ${VERSION} ${ARCH} from ${SOURCES_URL} ..."
	mkdir -p "${JAILMNT}/etc/pkg"
	cat <<EOF > "${JAILMNT}/etc/pkg/pkgbase.conf"
pkgbase: {
  url: "${SOURCES_URL%/}/FreeBSD:${VERSION}:${ARCH}/${PKGBASEREPO#/}"
  mirror_type: "${PKGBASEMIRROR}"
  enabled: yes
}
EOF
	cat <<EOF > "${JAILMNT}/etc/pkg/FreeBSD2.conf"
FreeBSD: { enabled: no }
FreeBSD-ports: { enabled: no }
FreeBSD-ports-kmods: { enabled: no }
FreeBSD-base: { enabled: no }
EOF

	pkg -o IGNORE_OSVERSION=yes -o REPOS_DIR="${JAILMNT}/etc/pkg" -o ABI="FreeBSD:${VERSION}:${ARCH}" -r ${JAILMNT}/ update
	# Omit the man/debug/kernel/src and tests packages, unneeded for us.
	pkg -o IGNORE_OSVERSION=yes -o REPOS_DIR="${JAILMNT}/etc/pkg" -o ABI="FreeBSD:${VERSION}:${ARCH}" -r ${JAILMNT}/ search -qCx '^FreeBSD-.*' | grep -vE -- '-man|-dbg|-kernel-|-tests|-src-' | xargs pkg -o REPOS_DIR="${JAILMNT}/etc/pkg" -r ${JAILMNT}/ install -y
	pkg -o IGNORE_OSVERSION=yes -o REPOS_DIR="${JAILMNT}/etc/pkg" -o ABI="FreeBSD:${VERSION}:${ARCH}" -r ${JAILMNT}/ search -q '^FreeBSD-src-sys' | xargs pkg -o REPOS_DIR="${JAILMNT}/etc/pkg" -r ${JAILMNT}/ install -y
	if [ -n "${KERNEL}" ]; then
		pkg -o IGNORE_OSVERSION=yes -o REPOS_DIR="${JAILMNT}/etc/pkg" -o ABI="FreeBSD:${VERSION}:${ARCH}" -r ${JAILMNT}/ install -y FreeBSD-kernel-"${KERNEL}" || \
			err 1 "Failed to install FreeBSD-kernel-${KERNEL}"
	fi

	rm "${JAILMNT}/etc/pkg/FreeBSD2.conf"
}

create_jail() {
	local IFS

	[ "${JAILNAME#*.*}" = "${JAILNAME}" ] ||
		err 1 "The jailname cannot contain a period (.). See jail(8)"

	if [ "${METHOD}" = "null" ]; then
		case "${JAILMNT:+set}" in
		set) ;;
		*)
			err ${EX_USAGE} "Must set -M to path of jail to use"
			;;
		esac
		case "${ALLOW_CLONING_HOST:-no}" in
		no)
			case "${JAILMNT}" in
			"/")
				err ${EX_USAGE} "Cannot use / for -M"
				;;
			esac
			;;
		esac
	fi

	if [ -z ${JAILMNT} ]; then
		case "${BASEFS:+set}" in
		set) ;;
		*)
			err ${EX_USAGE} "Please provide a BASEFS variable in your poudriere.conf"
			;;
		esac
		JAILMNT="${BASEFS}/jails/${JAILNAME}"
		_gsub "${JAILMNT}" ":" "_" JAILMNT
	fi

	[ "${JAILMNT#*:*}" = "${JAILMNT}" ] ||
		err 1 "The jail mount path cannot contain a colon (:)"

	case "${JAILFS:+set}.${NO_ZFS:+set}" in
	""."")
		case "${ZPOOL:+set}" in
		set) ;;
		*)
			err ${EX_USAGE} "Please provide a ZPOOL variable in your poudriere.conf"
			;;
		esac
		JAILFS=${ZPOOL}${ZROOTFS}/jails/${JAILNAME}
		;;
	esac

	if [ "${METHOD}" = "null" -a -n "${SRCPATH}" ]; then
		SRC_BASE="${SRCPATH}"
	else
		SRC_BASE="${JAILMNT}/usr/src"
	fi

	case ${METHOD} in
	ftp|http|gjb|ftp-archive|freebsdci|url=*)
		FCT=install_from_ftp
		;;
	svn*)
		[ -x "${SVN_CMD}" ] || \
		    err 1 "svn or svnlite not installed. Perhaps you need to 'pkg install subversion'"
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
			stable/*|head*|release/*|releng/*.[0-9]*|projects/*) ;;
			*)
				err 1 "version with svn should be: head[@rev], stable/N, release/N, releng/N or projects/X"
				;;
		esac
		FCT=install_from_vcs
		;;
	git*)
		if [ ! -x "${GIT_CMD}" ]; then
			err 1 "Git is not installed. Perhaps you need to 'pkg install git'"
		fi
		# Do not check valid version given one can have a specific branch
		FCT=install_from_vcs
		;;
	src=*)
		SRC_BASE="${METHOD#src=}"
		[ -d "${SRC_BASE}" ] || err 1 "No such source directory"
		FCT=install_from_src
		;;
	tar=*)
		FCT=install_from_tar
		TARBALL="${METHOD##*=}"
		case "${TARBALL:+set}" in
		set) ;;
		*)
			err ${EX_USAGE} "Must use format -m tar=/path/to/tarball.tar"
			;;
		esac
		[ -r "${TARBALL}" ] || err 1 "Cannot read file ${TARBALL}"
		METHOD="${METHOD%%=*}"
		;;
	pkgbase=*)
		FCT=install_from_pkgbase
		PKGBASEREPO="${METHOD##*=}"
		[ -n "${PKGBASEREPO}" ] ||
		    err 1 "Must specify repository to use -m pkgbase=repodir"
		[ -n "${SOURCES_URL}" ] ||
		    err 1 "Must specify URL to use -m pkgbase=repodir with -U"
		case "${SOURCES_URL}" in
		pkg+https://*) PKGBASEMIRROR="srv" ;;
		*) PKGBASEMIRROR="none" ;;
		esac
		METHOD="${METHOD%%=*}"
		;;
	pkgbase)
		FCT=install_from_pkgbase
		[ -z "${SOURCES_URL}" ] ||
		    err 1 "Cannot specify -U with -m pkgbase"
		SOURCES_URL="pkg+https://pkg.freebsd.org/"
		PKGBASEREPO='base_release_${VERSION_MINOR}'
		PKGBASEMIRROR="srv"
		;;
	null)
		JAILFS=none
		FCT=
		;;
	*)
		err 2 "Unknown method to create the jail"
		;;
	esac

	# Some methods determine VERSION from newvers.sh if possible
	# but need to have -v specified otherwise.
	case "${FCT}" in
	install_from_vcs) ;;	# Checkout is done in $FCT
	*)
		case "${VERSION:+set}" in
		"")
			if [ ! -r "${SRC_BASE:?}/sys/conf/newvers.sh" ]; then
				usage VERSION
			fi
			;;
		esac
		;;
	esac

	if [ "${JAILFS}" != "none" ]; then
		if [ -d "${JAILMNT}" ]; then
			err 1 "Directory ${JAILMNT} already exists"
		fi
	fi
	if [ "${METHOD}" = "null" ] && \
	    ([ ! -d "${JAILMNT}" ] || dirempty "${JAILMNT}"); then
		err 1 "Directory ${JAILMNT} expected to be populated from installworld already."
	fi
	if [ -n "${JAILFS}" -a "${JAILFS}" != "none" ]; then
		jset ${JAILNAME} fs ${JAILFS}
	fi
	if [ -n "${VERSION}" ]; then
		jset ${JAILNAME} version ${VERSION}
	fi
	jset ${JAILNAME} timestamp $(clock -epoch)
	jset ${JAILNAME} arch ${ARCH}
	jset ${JAILNAME} mnt ${JAILMNT}
	if [ -n "$SRCPATH" ]; then
		jset ${JAILNAME} srcpath ${SRCPATH}
	fi
	if [ -n "${KERNEL}" ]; then
		jset ${JAILNAME} kernel "${KERNEL}"
	fi

	# Wrap the jail creation in a special cleanup hook that will remove the jail
	# if any error is encountered
	CLEANUP_HOOK=cleanup_new_jail
	jset ${JAILNAME} method ${METHOD}
	if [ "${METHOD}" != "null" ]; then
		createfs ${JAILNAME} ${JAILMNT} ${JAILFS:-none}
	fi
	if [ -n "${FCT}" ]; then
		${FCT} version_extra
	fi

	jset ${JAILNAME} pkgbase ${BUILD_PKGBASE}

	if [ -r "${SRC_BASE:?}/sys/conf/newvers.sh" ]; then
		RELEASE=$(update_version "${version_extra}")
	else
		RELEASE="${VERSION}"
	fi
	[ -n "${RELEASE}" ] || err 1 "Failed to determine RELEASE"

	if [ "${METHOD}" = "null" ] && \
	    [ ! -f "${JAILMNT}/etc/login.conf" ]; then
		    err 1 "Directory ${JAILMNT} must be populated from installworld already."
	fi

	cleanup_confs
	markfs clean ${JAILMNT}

	# Check VERSION before running 'update_jail' on jails created using FreeBSD dists.
	case ${METHOD} in
		ftp|http|ftp-archive)
			if [ "${VERSION#*-RELEAS*}" != "${VERSION}" ]; then
				update_jail
			fi
			;;
	esac

	unset CLEANUP_HOOK

	msg "Jail ${JAILNAME} ${RELEASE} ${ARCH} is ready to be used"
}

info_jail() {
	local nbb nbf nbi nbq nbs tobuild
	local building_started status log
	local elapsed elapsed_days elapsed_hms elapsed_timestamp
	local now start_time timestamp
	local jversion jarch jmethod pmethod mnt fs kernel
	local pkgbase

	jail_exists ${JAILNAME} || err 1 "No such jail: ${JAILNAME}"

	POUDRIERE_BUILD_TYPE=bulk
	BUILDNAME=latest

	_log_path log
	now=$(clock -epoch)

	_bget status status || :
	_bget nbq stats_queued || nbq=0
	_bget nbb stats_built || nbb=0
	_bget nbf stats_failed || nbf=0
	_bget nbi stats_ignored || nbi=0
	_bget nbs stats_skipped || nbs=0
	tobuild=$((nbq - nbb - nbf - nbi - nbs))

	_jget jversion ${JAILNAME} version
	_jget jversion_vcs ${JAILNAME} version_vcs || jversion_vcs=
	_jget jarch ${JAILNAME} arch
	_jget jmethod ${JAILNAME} method
	_jget timestamp ${JAILNAME} timestamp || :
	_jget mnt ${JAILNAME} mnt || :
	_jget fs ${JAILNAME} fs || fs=""
	_jget kernel ${JAILNAME} kernel || kernel=
	_jget pkgbase ${JAILNAME} pkgbase || pkgbase=0

	echo "Jail name:         ${JAILNAME}"
	echo "Jail version:      ${jversion}"
	if [ -n "${jversion_vcs}" ]; then
		echo "Jail vcs version:  ${jversion_vcs}"
	fi
	echo "Jail arch:         ${jarch}"
	echo "Jail method:       ${jmethod}"
	echo "Jail mount:        ${mnt}"
	echo "Jail fs:           ${fs}"
	if [ -n "${kernel}" ]; then
		echo "Jail kernel:       ${kernel}"
	fi
	if [ -n "${timestamp}" ]; then
		echo "Jail updated:      $(date -j -r ${timestamp} "+%Y-%m-%d %H:%M:%S")"
	fi
	if [ "${pkgbase}" -eq 0 ]; then
	    echo "Jail pkgbase:      disabled"
	else
	    echo "Jail pkgbase:      enabled"
	fi
	if [ "${PTNAME_ARG:-0}" -eq 1 ] && porttree_exists ${PTNAME}; then
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

get_host_arch ARCH
REALARCH=${ARCH}
QUIET=0
NAMEONLY=0
PTNAME=default
SETNAME=""
XDEV=1
BUILD=0
GIT_DEPTH=--depth=1
BUILD_PKGBASE=0

set_command() {
	[ -z "${COMMAND}" ] || usage
	COMMAND="$1"
}

while getopts "bBiJ:j:v:a:z:m:nf:M:sdkK:lqcip:r:uU:t:z:P:S:DxXC:y" FLAG; do
	case "${FLAG}" in
		b)
			BUILD=1
			;;
		B)
			BUILD_PKGBASE=1
			;;
		i)
			set_command info
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
			if [ "${ARCH%.*}" = "${ARCH#*.}" ]; then
				ARCH="${ARCH#*.}"
			fi
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
			set_command start
			;;
		k)
			set_command stop
			;;
		K)
			KERNEL="${OPTARG:-GENERIC}"
			;;
		l)
			set_command list
			;;
		c)
			set_command create
			;;
		C)
			CLEANJAIL=${OPTARG}
			;;
		d)
			set_command delete
			;;
		p)
			PTNAME=${OPTARG}
			PTNAME_ARG=1
			;;
		P)
			[ -r ${OPTARG} ] || err 1 "No such patch"
			# If this is a relative path, add in ${PWD} as
			# a cd / was done.
			if [ "${OPTARG#/}" = "${OPTARG}" ]; then
				OPTARG="${SAVED_PWD}/${OPTARG}"
			fi
			SRCPATCHFILE="${OPTARG}"
			;;
		S)
			[ -d ${OPTARG} ] || err 1 "No such directory ${OPTARG}"
			SRCPATH=${OPTARG}
			;;
		D)
			GIT_DEPTH=""
			;;
		q)
			QUIET=1
			;;
		u)
			set_command update
			;;
		U)
			SOURCES_URL=${OPTARG}
			;;
		r)
			set_command rename
			NEWJAILNAME=${OPTARG}
			;;
		t)
			TORELEASE=${OPTARG}
			;;
		X)
			XDEV=0
			;;
		x)
			# Backwards compat
			;;
		y)
			YES=1
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

METHOD=${METHOD:-${METHOD_DEF}}
CLEANJAIL=${CLEANJAIL:-none}
if [ -n "${JAILNAME}" -a "${COMMAND}" != "create" ]; then
	_jget ARCH ${JAILNAME} arch || :
	_jget JAILFS ${JAILNAME} fs || :
	_jget JAILMNT ${JAILNAME} mnt || :
fi

# Handle common (jail+ports) git/svn methods and then fallback to
# methods only supported by jail.
if ! svn_git_checkout_method "${SOURCES_URL}" "${METHOD}" \
    "${SVN_HOST}/base" "${GIT_BASEURL}" \
    METHOD SVN_FULLURL GIT_FULLURL; then
	if [ -n "${SOURCES_URL}" ]; then
		usage
	fi
	case "${METHOD}" in
	csup) ;;
	freebsdci) ;;
	ftp) ;;
	ftp-archive) ;;
	gjb) ;;
	http) ;;
	null) ;;
	pkgbase=*) ;;
	pkgbase) ;;
	src=*) ;;
	tar=*) ;;
	url=*) ;;
	*)
		msg_error "Unknown method ${METHOD}"
		usage
		;;
	esac
fi

if [ -z "${KERNEL}" ] && [ "${BUILD_PKGBASE}" -eq 1 ]; then
    err 1 "pkgbase build need a kernel"
fi

case "${COMMAND}" in
	create)
		[ ${VERBOSE} -gt 0 ] || quiet="-q"
		if [ -z "${JAILNAME}" ]; then
			usage JAILNAME
		fi
		case ${METHOD} in
		src=*|null|git*) ;;
		*)
			if [ -z "${VERSION}" ]; then
				usage VERSION
			fi
			;;
		esac
		if jail_exists ${JAILNAME}; then
			err 2 "The jail ${JAILNAME} already exists"
		fi
		maybe_run_queued "${saved_argv}"
		check_emulation "${REALARCH}" "${ARCH}"
		create_jail
		;;
	info)
		if [ -z "${JAILNAME}" ]; then
			usage JAILNAME
		fi
		export MASTERNAME=${JAILNAME}-${PTNAME}${SETNAME:+-${SETNAME}}
		_mastermnt MASTERMNT
		export MASTERMNT
		info_jail
		;;
	list)
		list_jail
		;;
	stop)
		if [ -z "${JAILNAME}" ]; then
			usage JAILNAME
		fi
		maybe_run_queued "${saved_argv}"
		export MASTERNAME=${JAILNAME}-${PTNAME}${SETNAME:+-${SETNAME}}
		_mastermnt MASTERMNT
		export MASTERMNT
		jail_runs ${MASTERNAME} ||
		    msg "Jail ${MASTERNAME} not running, but cleaning up anyway"
		jail_stop
		;;
	start)
		export SET_STATUS_ON_START=0
		if [ -z "${JAILNAME}" ]; then
			usage JAILNAME
		fi
		porttree_exists ${PTNAME} || err 2 "No such ports tree ${PTNAME}"
		maybe_run_queued "${saved_argv}"
		export MASTERNAME=${JAILNAME}-${PTNAME}${SETNAME:+-${SETNAME}}
		_mastermnt MASTERMNT
		export MASTERMNT
		IMMUTABLE_BASE=no jail_start "${JAILNAME}" "${PTNAME}" \
		    "${SETNAME}"
		JNETNAME="n"
		;;
	delete)
		if [ -z "${JAILNAME}" ]; then
			usage JAILNAME
		fi
		jail_exists ${JAILNAME} || err 1 "No such jail: ${JAILNAME}"
		if [ -z "${YES}" ]; then
			confirm_if_tty "Are you sure you want to delete the jail?" || \
			    err 1 "Not deleting jail"
		fi
		maybe_run_queued "${saved_argv}"
		delete_jail
		;;
	update)
		[ ${VERBOSE} -gt 0 ] || quiet="-q"
		if [ -z "${JAILNAME}" ]; then
			usage JAILNAME
		fi
		jail_exists ${JAILNAME} || err 1 "No such jail: ${JAILNAME}"
		maybe_run_queued "${saved_argv}"
		if jail_runs ${JAILNAME}; then
			err 1 "Unable to update jail ${JAILNAME}: it is running"
		fi
		check_emulation "${REALARCH}" "${ARCH}"
		update_jail
		;;
	rename)
		if [ -z "${JAILNAME}" ]; then
			usage JAILNAME
		fi
		maybe_run_queued "${saved_argv}"
		rename_jail
		;;
	*)
		usage
		;;
esac
