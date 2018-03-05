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
    -b            -- Build the OS (for use with -m src)
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
                       allbsd, ftp-archive, ftp, git, http, null, src=PATH, svn,
                       svn+file, svn+http, svn+https, svn+ssh, tar=PATH
                       url=SOMEURL.
    -P patch      -- Specify a patch to apply to the source before building.
    -S srcpath    -- Specify a path to the source tree to be used.
    -D            -- Do a full git clone without --depth (default: --depth=1)
    -t version    -- Version of FreeBSD to upgrade the jail to.
    -U url        -- Specify a url to fetch the sources (with method git and/or svn).
    -x            -- Build and setup native-xtools cross compile tools in jail when
                     building for a different TARGET ARCH than the host.
                     Only applies if TARGET_ARCH and HOST_ARCH are different.
                     Will only be used if -m is svn*.

Options for -d:
    -C clean      -- Clean remaining data existing in pourdiere data folder.
                     See poudriere(8) for more details. Can be one of:
                       all, cache, logs, packages, wrkdirs
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
			_jget version_vcs ${name} version_vcs 2>/dev/null || \
			    version_vcs=
			_jget arch ${name} arch
			_jget method ${name} method
			_jget mnt ${name} mnt
			_jget timestamp ${name} timestamp 2>/dev/null || :
			time=
			[ -n "${timestamp}" ] && \
			    time="$(date -j -r ${timestamp} "+%Y-%m-%d %H:%M:%S")"
			if [ -n "${version_vcs}" ]; then
				version="${version} ${version_vcs}"
			fi
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
	local clean_dir depth

	test -z ${JAILNAME} && usage JAILNAME
	jail_exists ${JAILNAME} || err 1 "No such jail: ${JAILNAME}"
	jail_runs ${JAILNAME} &&
		err 1 "Unable to delete jail ${JAILNAME}: it is running"
	msg_n "Removing ${JAILNAME} jail..."
	method=$(jget ${JAILNAME} method)
	if [ "${method}" = "null" ]; then
		if [ -f "${JAILMNT}/etc/login.conf.orig" ]; then
			mv -f ${JAILMNT}/etc/login.conf.orig \
			    ${JAILMNT}/etc/login.conf
			cap_mkdb ${JAILMNT}/etc/login.conf
		fi
	else
		TMPFS_ALL=0 destroyfs ${JAILMNT} jail || :
	fi
	cache_dir="${POUDRIERE_DATA}/cache/${JAILNAME}-*"
	rm -rf ${POUDRIERED}/jails/${JAILNAME} ${cache_dir} \
		${POUDRIERE_DATA}/.m/${JAILNAME}-* || :
	echo " done"
	if [ "${CLEANJAIL}" = "none" ]; then
		return 0
	fi
	msg_n "Cleaning ${JAILNAME} data..."
	case ${CLEANJAIL} in
		all) cleandir="${POUDRIERE_DATA}" ;;
		cache) cleandir="${POUDRIERE_DATA}/cache"; depth=1 ;;
		logs) cleandir="${POUDRIERE_DATA}/logs"; depth=1 ;;
		packages) cleandir="${POUDRIERE_DATA}/packages"; depth=1 ;;
		wrkdirs) cleandir="${POUDRIERE_DATA}/wkdirs"; depth=1 ;;
	esac
	if [ -n "${clean_dir}" ]; then
		find "${clean_dir}/" -name "${JAILNAME}-*" \
			${depth:+-maxdepth ${depth}} -print0 | xargs -0 rm -rf || :
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
	[ ${QEMU_EMULATING} -eq 1 ] && \
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

hook_stop_jail() {
	jstop
	umountfs ${JAILMNT} 1
	if [ -n "${OLD_CLEANUP_HOOK}" ]; then
		${OLD_CLEANUP_HOOK}
	fi
}

update_jail() {
	METHOD=$(jget ${JAILNAME} method)
	: ${SRCPATH:=$(jget ${JAILNAME} srcpath 2>/dev/null || echo)}
	if [ "${METHOD}" = "null" -a -n "${SRCPATH}" ]; then
		SRC_BASE="${SRCPATH}"
	else
		SRC_BASE="${JAILMNT}/usr/src"
	fi
	if [ -z "${METHOD}" -o "${METHOD}" = "-" ]; then
		METHOD="ftp"
		jset ${JAILNAME} method ${METHOD}
	fi
	msg "Upgrading using ${METHOD}"
	: ${KERNEL:=$(jget ${JAILNAME} kernel 2>/dev/null || echo)}
	case ${METHOD} in
	ftp|http|ftp-archive)
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
		MASTERMNT=${JAILMNT}
		MASTERNAME=${JAILNAME}-${PTNAME}${SETNAME:+-${SETNAME}}
		[ -n "${RESOLV_CONF}" ] && cp -v "${RESOLV_CONF}" "${JAILMNT}/etc/"
		MUTABLE_BASE=yes NOLINUX=yes \
		    do_jail_mounts "${JAILMNT}" "${JAILMNT}" "${ARCH}" \
		    "${JAILNAME}"
		JNETNAME="n"
		jstart
		[ -n "${CLEANUP_HOOK}" ] && OLD_CLEANUP_HOOK="${CLEANUP_HOOK}"
		CLEANUP_HOOK=hook_stop_jail
		[ ${QEMU_EMULATING} -eq 1 ] && qemu_install "${JAILMNT}"
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
			# We're running inside the jail so basedir is /.
			# If we start using -b this needs to match it.
			basedir=/
			fu_workdir=/var/db/freebsd-update
			fu_bdhash="$(echo "${basedir}" | sha256 -q)"
			# New updates are identified by a symlink containing
			# the basedir hash and -install as suffix.  If we
			# really have new updates to install, then install them.
			if injail env PAGER=/bin/cat \
			    /usr/sbin/freebsd-update.fixed fetch && \
			    [ -L "${JAILMNT}${fu_workdir}/${fu_bdhash}-install" ]; then
				injail env PAGER=/bin/cat \
				    /usr/sbin/freebsd-update.fixed install
			fi
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
		if [ ${QEMU_EMULATING} -eq 1 ]; then
			[ -n "${EMULATOR}" ] || err 1 "No EMULATOR set"
			rm -f "${JAILMNT}${EMULATOR}"
			# Try to cleanup the lingering directory structure
			emulator_dir="${EMULATOR%/*}"
			while [ -n "${emulator_dir}" ] && \
			    rmdir "${JAILMNT}${emulator_dir}" 2>/dev/null; do
				emulator_dir="${emulator_dir%/*}"
			done
		fi
		jstop
		umountfs ${JAILMNT} 1
		if [ -n "${OLD_CLEANUP_HOOK}" ]; then
			CLEANUP_HOOK="${OLD_CLEANUP_HOOK}"
			unset OLD_CLEANUP_HOOK
		else
			unset CLEANUP_HOOK
		fi
		update_version
		[ -n "${RESOLV_CONF}" ] && rm -f ${JAILMNT}/etc/resolv.conf
		update_version_env $(jget ${JAILNAME} version)
		build_native_xtools
		markfs clean ${JAILMNT}
		;;
	svn*|git*)
		install_from_vcs version_extra
		RELEASE=$(update_version "${version_extra}")
		update_version_env "${RELEASE}"
		make -C ${SRC_BASE} delete-old delete-old-libs DESTDIR=${JAILMNT} BATCH_DELETE_OLD_FILES=yes
		markfs clean ${JAILMNT}
		;;
	src=*)
		SRC_BASE="${METHOD#src=}"
		install_from_src version_extra
		RELEASE=$(update_version "${version_extra}")
		update_version_env "${RELEASE}"
		make -C ${SRC_BASE} delete-old delete-old-libs DESTDIR=${JAILMNT} BATCH_DELETE_OLD_FILES=yes
		markfs clean ${JAILMNT}
		;;
	allbsd|gjb|url=*)
		[ -z "${VERSION}" ] && VERSION=$(jget ${JAILNAME} version)
		[ -z "${ARCH}" ] && ARCH=$(jget ${JAILNAME} arch)
		delete_jail
		create_jail
		;;
	csup|null|tar)
		err 1 "Upgrade is not supported with ${METHOD}; to upgrade, please delete and recreate the jail"
		;;
	*)
		err 1 "Unsupported method"
		;;
	esac
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
	    DESTDIR=${destdir} DB_FROM_SRC=1 || \
	    err 1 "Failed to 'make installworld'"
	${MAKE_CMD} -C "${SRC_BASE}" ${make_jobs} DESTDIR=${destdir} \
	    DB_FROM_SRC=1 distrib-dirs || \
	    err 1 "Failed to 'make distrib-dirs'"
	${MAKE_CMD} -C "${SRC_BASE}" ${make_jobs} DESTDIR=${destdir} \
	    distribution || err 1 "Failed to 'make distribution'"
	if [ -n "${KERNEL}" ]; then
		msg "Starting make installkernel"
		${MAKE_CMD} -C "${SRC_BASE}" ${make_jobs} installkernel \
		    KERNCONF=${KERNEL} DESTDIR=${destdir} || \
		    err 1 "Failed to 'make installkernel'"
	fi

	return 0
}

setup_build_env() {
	local hostver

	[ -n "${MAKE_CMD}" ] && return 0

	JAIL_OSVERSION=$(awk '/^\#define[[:blank:]]__FreeBSD_version/ {print $3}' ${SRC_BASE}/sys/sys/param.h)
	hostver=$(awk '/^\#define[[:blank:]]__FreeBSD_version/ {print $3}' /usr/include/sys/param.h)
	MAKE_CMD=make
	if [ ${hostver} -gt 1000000 -a ${JAIL_OSVERSION} -lt 1000000 ]; then
		FMAKE=$(command -v fmake 2>/dev/null)
		[ -n "${FMAKE}" ] ||
			err 1 "You need fmake installed on the host: devel/fmake"
		MAKE_CMD=${FMAKE}
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
}

setup_src_conf() {
	local src="$1"

	[ -f ${JAILMNT}/etc/${src}.conf ] && rm -f ${JAILMNT}/etc/${src}.conf
	touch ${JAILMNT}/etc/${src}.conf
	[ -f ${POUDRIERED}/${src}.conf ] && \
	    cat ${POUDRIERED}/${src}.conf > ${JAILMNT}/etc/${src}.conf
	[ -n "${SETNAME}" ] && \
	    [ -f ${POUDRIERED}/${SETNAME}-${src}.conf ] && \
	    cat ${POUDRIERED}/${SETNAME}-${src}.conf >> \
	    ${JAILMNT}/etc/${src}.conf
	[ -f ${POUDRIERED}/${JAILNAME}-${src}.conf ] && \
	    cat ${POUDRIERED}/${JAILNAME}-${src}.conf >> \
	    ${JAILMNT}/etc/${src}.conf
}

buildworld() {
	export SRC_BASE=${JAILMNT}/usr/src
	mkdir -p ${JAILMNT}/etc
	setup_src_conf "src"
	setup_src_conf "src-env"

	if [ "${TARGET}" = "mips" ]; then
		echo "WITH_ELFTOOLCHAIN_TOOLS=y" >> ${JAILMNT}/etc/src.conf
	fi

	export __MAKE_CONF=/dev/null
	export SRCCONF=${JAILMNT}/etc/src.conf
	export SRC_ENV_CONF=${JAILMNT}/etc/src-env.conf

	setup_build_env

	msg "Starting make buildworld with ${PARALLEL_JOBS} jobs"
	${MAKE_CMD} -C ${SRC_BASE} buildworld ${MAKE_JOBS} \
	    ${MAKEWORLDARGS} || err 1 "Failed to 'make buildworld'"
	BUILTWORLD=1

	if [ -n "${KERNEL}" ]; then
		msg "Starting make buildkernel with ${PARALLEL_JOBS} jobs"
		${MAKE_CMD} -C ${SRC_BASE} buildkernel ${MAKE_JOBS} \
			KERNCONF=${KERNEL} ${MAKEWORLDARGS} || \
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
	msg "Starting make native-xtools with ${PARALLEL_JOBS} jobs in ${XDEV_SRC}"
	# Can use -DNO_NXBTOOLCHAIN if we just ran buildworld to reuse the
	# toolchain already just built.
	${MAKE_CMD} -C ${XDEV_SRC} native-xtools ${MAKE_JOBS} \
	    ${BUILTWORLD:+-DNO_NXBTOOLCHAIN} \
	    ${MAKEWORLDARGS} || err 1 "Failed to 'make native-xtools' in ${XDEV_SRC}"
	rm -rf ${JAILMNT}/nxb-bin || err 1 "Failed to remove old native-xtools"
	# Check for native-xtools-install support
	NXTP=$(TARGET=${TARGET} TARGET_ARCH=${TARGET_ARCH} \
	    ${MAKE_CMD} -C ${XDEV_SRC} -f Makefile.inc1 -V NXTP)
	if [ -n "${NXTP}" ]; then
		# New style, we call native-xtools-install
		${MAKE_CMD} -C ${XDEV_SRC} native-xtools-install ${MAKE_JOBS} \
		    DESTDIR=${JAILMNT} NXTP=/nxb-bin || \
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
	cpdup -i0 ${cpignore_flag} ${SRC_BASE} ${JAILMNT}/usr/src
	[ -n "${cpignore}" ] && rm -f ${cpignore}
	echo " done"

	if [ ${BUILD} -eq 0 ]; then
		setup_build_env
		installworld
	else
		buildworld
		installworld
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
	local proto version_vcs
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
			${SVN_CMD} -q co ${SVN_FULLURL}/${VERSION} ${SRC_BASE} || err 1 " fail"
			echo " done"
			if [ -n "${SRCPATCHFILE}" ]; then
				msg_n "Patching the sources with ${SRCPATCHFILE}"
				${SVN_CMD} -q patch ${SRCPATCHFILE} ${SRC_BASE} || err 1 " fail"
				echo done
			fi
			;;
		git*)
			if [ -n "${SRCPATCHFILE}" ]; then
				err 1 "Patch files not supported with git, please use feature branches"
			fi
			msg_n "Checking out the sources with ${METHOD}..."
			${GIT_CMD} clone ${GIT_DEPTH} -q -b ${VERSION} ${GIT_FULLURL} ${SRC_BASE} || err 1 " fail"
			echo " done"
			# No support for patches, using feature branches is recommanded"
			;;
		esac
	else
		case ${METHOD} in
		svn*)
			msg_n "Updating the sources with ${METHOD}..."
			${SVN_CMD} upgrade ${SRC_BASE} 2>/dev/null || :
			${SVN_CMD} -q update -r ${TORELEASE:-head} ${SRC_BASE} || err 1 " fail"
			echo " done"
			;;
		git*)
			${GIT_CMD} -C ${SRC_BASE} pull --rebase -q || err 1 " fail"
			if [ -n "${TORELEASE}" ]; then
				${GIT_CMD} checkout -q "${TORELEASE}" || err 1 " fail"
			fi
			echo " done"
			;;
		esac
	fi
	buildworld
	installworld
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
	[ -z "${SRCPATH}" ] && DISTS="${DISTS} src"
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
					URL="${FREEBSD_HOST}/ftp/${type}/${ARCH}/${V}"
					;;
				*)
					URL="${FREEBSD_HOST}/pub/FreeBSD/${type}/${ARCH}/${V}"
					;;
			esac
			;;
		url=*) URL=${METHOD##url=} ;;
		allbsd) URL="https://pub.allbsd.org/FreeBSD-snapshots/${ARCH%%.*}-${ARCH##*.}/${V}-JPSNAP/ftp" ;;
		ftp-archive) URL="http://ftp-archive.freebsd.org/pub/FreeBSD-Archive/old-releases/${ARCH}/${V}" ;;
		esac
		DISTS="${DISTS} dict"
		[ "${NO_LIB32:-no}" = "no" -a "${ARCH}" = "amd64" ] &&
			DISTS="${DISTS} lib32"
		[ -n "${KERNEL}" ] && DISTS="${DISTS} kernels"
		for dist in ${DISTS}; do
			fetch_file ${JAILMNT}/fromftp/ "${URL}/$dist/CHECKSUM.${HASH}" ||
				err 1 "Fail to fetch checksum file"
			sed -n "s/.*(\(.*\...\)).*/\1/p" \
				${JAILMNT}/fromftp/CHECKSUM.${HASH} | \
				while read pkg; do
				[ ${pkg} = "install.sh" ] && continue
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
						URL="${FREEBSD_HOST}/ftp/${type}/${ARCH%%.*}/${ARCH##*.}/${V}"
						;;
					*)
						URL="${FREEBSD_HOST}/pub/FreeBSD/${type}/${ARCH%%.*}/${ARCH##*.}/${V}"
						;;
				esac
				;;
			allbsd) URL="https://pub.allbsd.org/FreeBSD-snapshots/${ARCH%%.*}-${ARCH##*.}/${V}-JPSNAP/ftp" ;;
			ftp-archive) URL="http://ftp-archive.freebsd.org/pub/FreeBSD-Archive/old-releases/${ARCH%%.*}/${ARCH##*.}/${V}" ;;
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

		DISTS="${DISTS} lib32"
		[ -n "${KERNEL}" ] && DISTS="${DISTS} kernel"
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
	rm -rf ${JAILMNT}/fromftp/
	echo " done"

	build_native_xtools
}

install_from_tar() {
	msg_n "Installing ${VERSION} ${ARCH} from ${TARBALL} ..."
	tar -xpf ${TARBALL} -C ${JAILMNT}/ || err 1 " fail"
	echo " done"
	build_native_xtools
}

create_jail() {
	[ "${JAILNAME#*.*}" = "${JAILNAME}" ] ||
		err 1 "The jailname cannot contain a period (.). See jail(8)"

	if [ "${METHOD}" = "null" ]; then
		[ -z "${JAILMNT}" ] && \
		    err 1 "Must set -M to path of jail to use"
		[ "${JAILMNT}" = "/" ] && \
		    err 1 "Cannot use / for -M"
	fi

	if [ -z ${JAILMNT} ]; then
		[ -z ${BASEFS} ] && err 1 "Please provide a BASEFS variable in your poudriere.conf"
		JAILMNT="${BASEFS}/jails/${JAILNAME}"
		_gsub "${JAILMNT}" ":" "_"
		JAILMNT="${_gsub}"
	fi

	[ "${JAILMNT#*:*}" = "${JAILMNT}" ] ||
		err 1 "The jail mount path cannot contain a colon (:)"

	if [ -z "${JAILFS}" -a -z "${NO_ZFS}" ]; then
		[ -z ${ZPOOL} ] && err 1 "Please provide a ZPOOL variable in your poudriere.conf"
		JAILFS=${ZPOOL}${ZROOTFS}/jails/${JAILNAME}
	fi

	if [ "${METHOD}" = "null" -a -n "${SRCPATH}" ]; then
		SRC_BASE="${SRCPATH}"
	else
		SRC_BASE="${JAILMNT}/usr/src"
	fi

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
			stable/*|head*|release/*|releng/*.[0-9]*|projects/*) ;;
			*)
				err 1 "version with svn should be: head[@rev], stable/N, release/N, releng/N or projects/X"
				;;
		esac
		FCT=install_from_vcs
		;;
	git*)
		# Do not check valid version given one can have a specific branch
		FCT=install_from_vcs
		;;
	src=*)
		SRC_BASE="${METHOD#src=}"
		test -d ${SRC_BASE} || err 1 "No such source directory"
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

	if [ "${JAILFS}" != "none" ]; then
		[ -d "${JAILMNT}" ] && \
		    err 1 "Directory ${JAILMNT} already exists"
	fi
	if [ "${METHOD}" != "null" ]; then
		createfs ${JAILNAME} ${JAILMNT} ${JAILFS:-none}
	elif [ ! -d "${JAILMNT}" ] || dirempty "${JAILMNT}"; then
		err 1 "Directory ${JAILMNT} expected to be populated from installworld already."
	fi
	[ -n "${JAILFS}" -a "${JAILFS}" != "none" ] && jset ${JAILNAME} fs ${JAILFS}
	if [ -n "${VERSION}" ]; then
		jset ${JAILNAME} version ${VERSION}
	fi
	jset ${JAILNAME} timestamp $(clock -epoch)
	jset ${JAILNAME} arch ${ARCH}
	jset ${JAILNAME} mnt ${JAILMNT}
	[ -n "$SRCPATH" ] && jset ${JAILNAME} srcpath ${SRCPATH}
	[ -n "${KERNEL}" ] && jset ${JAILNAME} kernel ${KERNEL}

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

	[ "${METHOD}" = "null" ] && \
	    [ ! -f "${JAILMNT}/etc/login.conf" ] && \
	    err 1 "Directory ${JAILMNT} must be populated from installworld already."

	cp -f "${JAILMNT}/etc/login.conf" "${JAILMNT}/etc/login.conf.orig"
	update_version_env "${RELEASE}"

	pwd_mkdb -d ${JAILMNT}/etc/ -p ${JAILMNT}/etc/master.passwd

	markfs clean ${JAILMNT}

	# Check VERSION before running 'update_jail' on jails created using FreeBSD dists.
	case ${METHOD} in
		ftp|http|ftp-archive)
			[ ${VERSION#*-RELEAS*} != ${VERSION} ] && update_jail
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

	jail_exists ${JAILNAME} || err 1 "No such jail: ${JAILNAME}"

	POUDRIERE_BUILD_TYPE=bulk
	BUILDNAME=latest

	_log_path log
	now=$(clock -epoch)

	_bget status status 2>/dev/null || :
	_bget nbq stats_queued 2>/dev/null || nbq=0
	_bget nbb stats_built 2>/dev/null || nbb=0
	_bget nbf stats_failed 2>/dev/null || nbf=0
	_bget nbi stats_ignored 2>/dev/null || nbi=0
	_bget nbs stats_skipped 2>/dev/null || nbs=0
	tobuild=$((nbq - nbb - nbf - nbi - nbs))

	_jget jversion ${JAILNAME} version
	_jget jversion_vcs ${JAILNAME} version_vcs 2>/dev/null || jversion_vcs=
	_jget jarch ${JAILNAME} arch
	_jget jmethod ${JAILNAME} method
	_jget timestamp ${JAILNAME} timestamp 2>/dev/null || :
	_jget mnt ${JAILNAME} mnt 2>/dev/null || :
	_jget fs ${JAILNAME} fs 2>/dev/null || fs=""
	_jget kernel ${JAILNAME} kernel 2>/dev/null || kernel=

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
XDEV=0
BUILD=0
GIT_DEPTH=--depth=1

while getopts "biJ:j:v:a:z:m:nf:M:sdkK:lqcip:r:uU:t:z:P:S:DxC:" FLAG; do
	case "${FLAG}" in
		b)
			BUILD=1
			;;
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
		K)
			KERNEL=${OPTARG:-GENERIC}
			;;
		l)
			LIST=1
			;;
		c)
			CREATE=1
			;;
		C)
			CLEANJAIL=${OPTARG}
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
		D)
			GIT_DEPTH=""
			;;
		q)
			QUIET=1
			;;
		u)
			UPDATE=1
			;;
		U)
			SOURCES_URL=${OPTARG}
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
post_getopts

METHOD=${METHOD:-ftp}
CLEANJAIL=${CLEAN:-none}
if [ -n "${JAILNAME}" -a ${CREATE} -eq 0 ]; then
	_jget ARCH ${JAILNAME} arch 2>/dev/null || :
	_jget JAILFS ${JAILNAME} fs 2>/dev/null || :
	_jget JAILMNT ${JAILNAME} mnt 2>/dev/null || :
fi

if [ -n "${SOURCES_URL}" ]; then
	case "${METHOD}" in
	svn*)
		case "${SOURCES_URL}" in
		http://*) METHOD="svn+http" ;;
		https://*) METHOD="svn+https" ;;
		file://*) METHOD="svn+file" ;;
		svn+ssh://*) METHOD="svn+ssh" ;;
		svn://*) METHOD="svn" ;;
		*) err 1 "Invalid svn url" ;;
		esac
		;;
	git*)
		case "${SOURCES_URL}" in
		ssh://*) METHOD="git+ssh" ;;
		http://*) METHOD="git+http" ;;
		https://*) METHOD="git+https" ;;
		git://*) METHOD="git" ;;
		file://*) METHOD="git" ;;
		*) err 1 "Invalid git url" ;;
		esac
		;;
	*)
		err 1 "-U only valid with git and svn methods"
		;;
	esac
	SVN_FULLURL=${SOURCES_URL}
	GIT_FULLURL=${SOURCES_URL}
else
	case ${METHOD} in
	svn+http) proto="http" ;;
	svn+https) proto="https" ;;
	svn+ssh) proto="svn+ssh" ;;
	svn+file) proto="file" ;;
	svn) proto="svn" ;;
	git+ssh) proto="ssh" ;;
	git+http) proto="http" ;;
	git+https) proto="https" ;;
	git) proto="git" ;;
	esac
	SVN_FULLURL=${proto}://${SVN_HOST}/base
	GIT_FULLURL=${proto}://${GIT_BASEURL}
fi


case "${CREATE}${INFO}${LIST}${STOP}${START}${DELETE}${UPDATE}${RENAME}" in
	10000000)
		test -z ${JAILNAME} && usage JAILNAME
		case ${METHOD} in
			src=*|null|tar) ;;
			*) test -z ${VERSION} && usage VERSION ;;
		esac
		jail_exists ${JAILNAME} && \
		    err 2 "The jail ${JAILNAME} already exists"
		maybe_run_queued "${saved_argv}"
		check_emulation "${REALARCH}" "${ARCH}"
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
		MUTABLE_BASE=yes jail_start ${JAILNAME} ${PTNAME} ${SETNAME}
		JNETNAME="n"
		;;
	00000100)
		test -z ${JAILNAME} && usage JAILNAME
		confirm_if_tty "Are you sure you want to delete the jail?" || \
		    err 1 "Not deleting jail"
		maybe_run_queued "${saved_argv}"
		delete_jail
		;;
	00000010)
		test -z ${JAILNAME} && usage JAILNAME
		jail_exists ${JAILNAME} || err 1 "No such jail: ${JAILNAME}"
		maybe_run_queued "${saved_argv}"
		jail_runs ${JAILNAME} && \
		    err 1 "Unable to update jail ${JAILNAME}: it is running"
		check_emulation "${REALARCH}" "${ARCH}"
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
