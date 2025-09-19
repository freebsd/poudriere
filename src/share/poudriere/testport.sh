#!/bin/sh
# 
# Copyright (c) 2010-2013 Baptiste Daroussin <bapt@FreeBSD.org>
# Copyright (c) 2010-2011 Julien Laffaye <jlaffaye@FreeBSD.org>
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

usage() {
	cat << EOF
poudriere testport [parameters] [options]

Parameters:
    -j jailname -- Run inside the given jail
    [-o] origin   -- Specify an origin in the portstree

Options:
    -B name     -- What buildname to use (must be unique, defaults to
                   YYYY-MM-DD_HH:MM:SS). Resuming a previous build will not
                   retry built/failed/skipped/ignored packages.
    -b branch   -- Branch to choose for fetching packages from official
                   repositories: valid options are: latest, quarterly,
                   release_*, or a url.
    -c          -- Run make config for the given port
    -i          -- Interactive mode. Enter jail for interactive testing and
                   automatically cleanup when done.
    -I          -- Advanced Interactive mode. Leaves jail running with port
                   installed after test.
    -J n[:p]    -- Run n jobs in parallel for dependencies, and optionally
                   run a different number of jobs in parallel while preparing
                   the build. (Defaults to the number of CPUs for n and
                   1.25 times n for p)
    -k          -- Don't consider failures as fatal; find all failures.
    -n          -- Dry-run. Show what will be done, but do not build
                   any packages.
    -N          -- Do not build package repository when build is completed
    -NN         -- Do not commit package repository when build is completed
    -O overlays -- Specify extra ports trees to overlay
    -p tree     -- Specify the path to the ports tree
    -P          -- Use custom prefix
    -S          -- Don't recursively rebuild packages affected by other
                   packages requiring incremental rebuild. This can result
                   in broken packages if the ones updated do not retain
                   a stable ABI.
    -v          -- Be verbose; show more information. Use twice to enable
                   debug output
    -w          -- Save WRKDIR on failed builds
    -z set      -- Specify which SET to use
EOF
	exit ${EX_USAGE}
}

CONFIGSTR=0
NOPREFIX=1
DRY_RUN=0
SETNAME=""
INTERACTIVE_MODE=0
PTNAME="default"
BUILD_REPO=1
OVERLAYS=""
COMMIT=1

while getopts "b:B:o:cniIj:J:kNO:p:PSvwz:" FLAG; do
	case "${FLAG}" in
		b)
			PACKAGE_FETCH_BRANCH="${OPTARG}"
			validate_package_branch "${PACKAGE_FETCH_BRANCH}"
			;;
		B)
			BUILDNAME="${OPTARG}"
			;;
		c)
			CONFIGSTR=1
			;;
		o)
			ORIGINSPEC=${OPTARG}
			;;
		n)
			[ "${ATOMIC_PACKAGE_REPOSITORY}" = "yes" ] ||
			    err 1 "ATOMIC_PACKAGE_REPOSITORY required for dry-run support"
			DRY_RUN=1
			DRY_MODE="${COLOR_DRY_MODE}[Dry Run]${COLOR_RESET} "
			;;
		j)
			jail_exists ${OPTARG} || err 1 "No such jail: ${OPTARG}"
			JAILNAME="${OPTARG}"
			;;
		J)
			BUILD_PARALLEL_JOBS=${OPTARG%:*}
			PREPARE_PARALLEL_JOBS=${OPTARG#*:}
			;;
		k)
			PORTTESTING_FATAL=no
			;;
		i)
			INTERACTIVE_MODE=1
			;;
		I)
			INTERACTIVE_MODE=2
			;;
		N)
			: ${NFLAG:=0}
			NFLAG=$((NFLAG + 1))
			BUILD_REPO=0
			if [ "${NFLAG}" -eq 2 ]; then
				# Don't commit the packages.  This is effectively
				# the same as -n but does an actual build.
				if [ "${ATOMIC_PACKAGE_REPOSITORY}" != "yes" ]; then
					err ${EX_USAGE} "-NN only makes sense with ATOMIC_PACKAGE_REPOSITORY=yes"
				fi
				COMMIT=0
			fi
			;;
		O)
			porttree_exists ${OPTARG} ||
			    err 2 "No such overlay ${OPTARG}"
			OVERLAYS="${OVERLAYS} ${OPTARG}"
			;;
		p)
			porttree_exists ${OPTARG} ||
			    err 2 "No such ports tree ${OPTARG}"
			PTNAME=${OPTARG}
			;;
		P)
			NOPREFIX=0
			;;
		S)
			SKIP_RECURSIVE_REBUILD=1
			;;
		w)
			SAVE_WRKDIR=1
			;;
		z)
			[ -n "${OPTARG}" ] || err 1 "Empty set name"
			SETNAME="${OPTARG}"
			;;
		v)
			VERBOSE=$((VERBOSE + 1))
			;;
		*)
			usage
			;;
	esac
done

encode_args saved_argv "$@"
shift $((OPTIND-1))
post_getopts

if [ -z ${ORIGINSPEC} ]; then
	if [ $# -ne 1 ]; then
		usage
	fi
	ORIGINSPEC="${1}"
fi

if [ -z "${JAILNAME}" ]; then
	err 1 "Don't know on which jail to run please specify -j"
fi

maybe_run_queued "${saved_argv}"

: ${BUILD_PARALLEL_JOBS:=${PARALLEL_JOBS}}
: ${PREPARE_PARALLEL_JOBS:=$(echo "scale=0; ${PARALLEL_JOBS} * 1.25 / 1" | bc)}
PARALLEL_JOBS=${PREPARE_PARALLEL_JOBS}

MASTERNAME=${JAILNAME}-${PTNAME}${SETNAME:+-${SETNAME}}
_mastermnt MASTERMNT
export MASTERNAME
export MASTERMNT
export POUDRIERE_BUILD_TYPE=bulk

jail_start "${JAILNAME}" "${PTNAME}" "${SETNAME}"

_pget portsdir ${PTNAME} mnt
fetch_global_port_vars || \
    err 1 "Failed to lookup global ports metadata"
originspec_decode "${ORIGINSPEC}" ORIGIN FLAVOR SUBPKG
# Remove excess slashes for mistakes
ORIGIN="${ORIGIN#/}"
ORIGIN="${ORIGIN%/}"
originspec_encode ORIGINSPEC "${ORIGIN}" "${FLAVOR}" "${SUBPKG}"
if have_ports_feature FLAVORS; then
	case "${FLAVOR}" in
	"${FLAVOR_ALL}")
		err 1 "Cannot testport on multiple flavors, use 'bulk -t' instead."
		;;
	esac
	case "${FLAVOR_DEFAULT_ALL}" in
	"yes")
		err 1 "FLAVOR_DEFAULT_ALL is set. Cannot testport on multiple flavors, use 'bulk -t' instead."
		;;
	esac
else
	case "${FLAVOR}" in
	"")
		err 1 "Trying to build FLAVOR-specific ${ORIGINSPEC} but ports tree has no FLAVORS support."
		;;
	esac
fi

_lookup_portdir portdir "${ORIGIN}"
if [ $CONFIGSTR -eq 1 ]; then
	# XXX: This does not handle MOVED
	command -v portconfig >/dev/null 2>&1 || \
	    command -v dialog4ports >/dev/null 2>&1 || \
	    err 1 "You must have ports-mgmt/dialog4ports or ports-mgmt/portconfig installed on the host to use -c."
	__MAKE_CONF="$(mktemp -t poudriere-make.conf)"
	setup_makeconf "${__MAKE_CONF}" "${JAILNAME}" "${PTNAME}" "${SETNAME}"
	PORTSDIR="${portsdir:?}" \
	    __MAKE_CONF="${__MAKE_CONF:?}" \
	    PORT_DBDIR="${MASTERMNT:?}/var/db/ports" \
	    TERM=${SAVED_TERM} \
	    make -C "${MASTERMNT:?}${portdir:?}" \
	    ${FLAVOR:+"FLAVOR=${FLAVOR}"} \
	    config
	rm -f "${__MAKE_CONF:?}"
fi

# deps_fetch_vars lookup for dependencies moved to prepare_ports()
LISTPORTS="${ORIGINSPEC:?}"
CLEAN_LISTED=1
prepare_ports
if check_moved "${ORIGINSPEC}" new_originspec 1; then
	msg "MOVED: ${COLOR_PORT}${ORIGINSPEC}${COLOR_RESET} moved to ${COLOR_PORT}${new_originspec}${COLOR_RESET}"
	case "${new_originspec}" in
	"EXPIRED "*) ;;
	"") ;;
	*)
		# The ORIGIN may have a FLAVOR in it which overrides what
		# user specified.
		originspec_decode "${new_originspec}" ORIGIN NEW_FLAVOR NEW_SUBPKG
		case "${NEW_FLAVOR:+set}" in
		set) FLAVOR="${NEW_FLAVOR}" ;;
		esac
		case "${NEW_SUBPKG:+set}" in
		set) SUBPKG="${NEW_SUBPKG}" ;;
		esac
		# Update ORIGINSPEC for the new ORIGIN
		originspec_encode ORIGINSPEC "${ORIGIN}" "${FLAVOR}" "${SUBPKG}"
		;;
	esac
fi
# Ensure the port exists after handling MOVED.
_lookup_portdir portdir "${ORIGIN}"
if [ "${portdir:?}" = "${PORTSDIR:?}/${ORIGIN:?}" ] &&
	[ ! -f "${portsdir:?}/${ORIGIN:?}/Makefile" ] ||
	[ -d "${portsdir:?}/${ORIGIN:?}/../Mk" ]; then
	err 1 "Nonexistent origin ${COLOR_PORT}${ORIGIN}${COLOR_RESET}"
fi
get_pkgname_from_originspec "${ORIGINSPEC:?}" PKGNAME ||
    err "${EX_SOFTWARE}" "Failed to find PKGNAME for ${ORIGINSPEC}"
shash_get pkgname-ignore "${PKGNAME:?}" IGNORE || :
if have_ports_feature FLAVORS; then
	shash_get origin-flavors "${ORIGIN:?}" FLAVORS || FLAVORS=
	case "${FLAVORS:+set}" in
	set)
		case "${FLAVOR}" in
		""|"${FLAVOR_DEFAULT}")
			FLAVOR="${FLAVORS%% *}"
			originspec_encode ORIGINSPEC "${ORIGIN}" "${FLAVOR}" \
			    "${SUBPKG}"
			;;
		esac
		;;
	esac
fi
# Unqueue our test port so parallel_build() does not build it.
echo "${PKGNAME:?}" | pkgqueue_remove_many_pipe build

show_dry_run_summary
markfs prepkg ${MASTERMNT}

_log_path log

PARALLEL_JOBS=${BUILD_PARALLEL_JOBS}

POUDRIERE_BUILD_TYPE=bulk parallel_build ${JAILNAME} ${PTNAME} ${SETNAME}
if [ $(bget stats_failed) -gt 0 ] || [ $(bget stats_skipped) -gt 0 ]; then
	failed=$(bget ports.failed | awk '{print $1 ":" $3 }' | xargs echo)
	skipped=$(bget ports.skipped | awk '{print $1}' | sort -u | xargs echo)

	msg_error "Depends failed to build"
	COLOR_ARROW="${COLOR_FAIL}" \
	    msg "${COLOR_FAIL}Failed ports: ${COLOR_PORT}${failed}"
	if [ -n "${skipped}" ]; then
		COLOR_ARROW="${COLOR_SKIP}" \
		    msg "${COLOR_SKIP}Skipped ports: ${COLOR_PORT}${skipped}"
	fi

	bset_job_status "failed/depends" "${ORIGINSPEC}" "${PKGNAME}"
	show_build_summary
	show_log_info
	set +e
	exit 1
fi
nbbuilt=$(bget stats_built)

if [ ${BUILD_REPO} -eq 1 -a ${nbbuilt} -gt 0 ]; then
	build_repo
fi

commit_packages

bset_job_status "testing" "${ORIGINSPEC}" "${PKGNAME}"

[ -n "${LOCALBASE}" ] || err 1 "Port has empty LOCALBASE?"
[ -n "${PREFIX}" ] || err 1 "Port has empty PREFIX?"
if [ "${USE_PORTLINT}" = "yes" ]; then
	if [ ! -x `command -v portlint` ]; then
		err 2 "First install portlint if you want USE_PORTLINT to work as expected"
	fi
	msg "Portlint check"
	(
		if cd "${MASTERMNT:?}${portdir:?}"; then
			PORTSDIR="${MASTERMNT:?}${PORTSDIR:?}" portlint -C |
			    tee "${log:?}/logs/${PKGNAME:?}.portlint.log"
		fi
	) || :
fi
if [ ${NOPREFIX} -ne 1 ]; then
	PREFIX="${BUILDROOT:-/prefix}/`echo ${PKGNAME} | tr '[,+]' _`"
fi
if [ "${PREFIX}" != "${LOCALBASE}" ]; then
	PORT_FLAGS="PREFIX=${PREFIX}"
fi
msg "Building with flags: ${PORT_FLAGS}"

if [ -d "${MASTERMNT:?}${PREFIX:?}" -a "${PREFIX:?}" != "/usr" ]; then
	msg "Removing existing ${PREFIX}"
	if [ "${PREFIX:?}" != "${LOCALBASE:?}" ]; then
		rm -Rfx "${MASTERMNT:?}${PREFIX}"
	fi
fi

PKGENV="PACKAGES=/tmp/pkgs PKGREPOSITORY=/tmp/pkgs PKGLATESTREPOSITORY=/tmp/pkgs/Latest"
MAKE_ARGS="${FLAVOR:+ FLAVOR=${FLAVOR}}"
injail install -d -o ${PORTBUILD_USER} /tmp/pkgs
PORTTESTING=1
export TRYBROKEN=yes
export NO_WARNING_PKG_INSTALL_EOL=yes
# Disable waits unless running in a tty interactively
if ! [ -t 1 ]; then
	export WARNING_WAIT=0
	export DEV_WARNING_WAIT=0
fi
sed -i '' '/DISABLE_MAKE_JOBS=poudriere/d' "${MASTERMNT:?}/etc/make.conf"
_gsub_var_name "${PKGNAME%-*}" PKGNAME_VARNAME
eval "MAX_FILES=\${MAX_FILES_${PKGNAME_VARNAME}:-${DEFAULT_MAX_FILES}}"
eval "MAX_MEMORY=\${MAX_MEMORY_${PKGNAME_VARNAME}:-${MAX_MEMORY:-}}"
if [ -n "${MAX_MEMORY}" -o -n "${MAX_FILES}" ]; then
	JEXEC_LIMITS=1
fi
unset PKGNAME_VARNAME
log_start "${PKGNAME}" 1
buildlog_start "${PKGNAME}" "${ORIGINSPEC}"
ret=0

# Don't show timestamps in msg() which goes to logs, only job_msg()
# which goes to master
NO_ELAPSED_IN_MSG=1
TIME_START_JOB=$(clock -monotonic)
build_port "${ORIGINSPEC}" "${PKGNAME}" || ret=$?
unset NO_ELAPSED_IN_MSG
now=$(clock -monotonic)
elapsed=$((now - TIME_START_JOB))

if [ ${ret} -ne 0 ]; then
	if [ ${ret} -eq 2 ]; then
		failed_phase=$(awk -f ${AWKPREFIX:?}/processonelog2.awk \
			"${log:?}/logs/${PKGNAME:?}.log" \
			2> /dev/null)
	else
		failed_status=$(bget status)
		failed_phase=${failed_status%%:*}
	fi

	save_wrkdir "${MASTERMNT:?}" "${ORIGINSPEC}" "${PKGNAME}" \
	    "${failed_phase}" || :

	ln -s "../${PKGNAME:?}.log" "${log:?}/logs/errors/${PKGNAME:?}.log"
	bset_job_status "processlog" "${ORIGINSPEC}" "${PKGNAME}"
	errortype="$(awk -f ${AWKPREFIX:?}/processonelog.awk \
		"${log:?}/logs/errors/${PKGNAME:?}.log" \
		2> /dev/null)" || :
	bset_job_status "${status%%:*}" "${ORIGINSPEC}" "${PKGNAME}"
	badd ports.failed "${ORIGINSPEC} ${PKGNAME} ${failed_phase} ${errortype} ${elapsed}"
	update_stats || :

	if [ ${INTERACTIVE_MODE} -eq 0 ]; then
		stop_build "${PKGNAME}" "${ORIGINSPEC}" 1
		log_stop
		bset_job_status "failed/${failed_phase}" "${ORIGINSPEC}" \
		    "${PKGNAME}"
		msg_error "Build failed in phase: ${COLOR_PHASE}${failed_phase}${COLOR_RESET}"
		show_build_summary
		show_log_info
		set +e
		exit 1
	fi
else
	ln -s "../${PKGNAME:?}.log" "${log:?}/logs/built/${PKGNAME:?}.log"
	badd ports.built "${ORIGINSPEC} ${PKGNAME} ${elapsed}"
	if [ -f "${MASTERMNT:?}${portdir:?}/.keep" ]; then
		save_wrkdir "${MASTERMNT:?}" "${ORIGINSPEC}" "${PKGNAME}" \
		    "noneed" || :
	fi
	update_stats || :
fi

if [ ${INTERACTIVE_MODE} -gt 0 ]; then
	# Stop the tee process and stop redirecting stdout so that
	# the terminal can be properly used in the jail
	log_stop

	enter_interactive

	if [ ${INTERACTIVE_MODE} -eq 1 ]; then
		# Since failure was skipped earlier, fail now after leaving
		# jail.
		if [ -n "${failed_phase}" ]; then
			stop_build "${PKGNAME}" "${ORIGINSPEC}" 1
			bset_job_status "failed/${failed_phase}" \
			    "${ORIGINSPEC}" "${PKGNAME}"
			msg_error "Build failed in phase: ${COLOR_PHASE}${failed_phase}${COLOR_RESET}"
			show_build_summary
			show_log_info
			set +e
			exit 1
		fi
	elif [ ${INTERACTIVE_MODE} -eq 2 ]; then
		exit 0
	fi
else
	if [ -f "${MASTERMNT:?}/tmp/pkgs/${PKGNAME:?}.${PKG_EXT}" ]; then
		msg "Installing from package"
		if ! ensure_pkg_installed; then
			stop_build "${PKGNAME}" "${ORIGINSPEC}" 1
			log_stop
			bset_job_status "crashed" "${ORIGINSPEC}" "${PKGNAME}"
			err 1 "Unable to extract pkg."
		fi
		injail ${PKG_ADD} "/tmp/pkgs/${PKGNAME:?}.${PKG_EXT}" || :
	fi
fi

msg "Cleaning up"
injail /usr/bin/make -C "${portdir:?}" -DNOCLEANDEPENDS clean \
    ${MAKE_ARGS}

if [ -z "${POUDRIERE_INTERACTIVE_NO_INSTALL-}" ]; then
	msg "Deinstalling package"
	ensure_pkg_installed
	injail ${PKG_DELETE} "${PKGNAME:?}"
fi

stop_build "${PKGNAME}" "${ORIGINSPEC}" ${ret}
log_stop

bset_job_status "stopped" "${ORIGINSPEC}" "${PKGNAME}"

bset status "done:"

show_build_summary
show_log_info

set +e

exit 0
