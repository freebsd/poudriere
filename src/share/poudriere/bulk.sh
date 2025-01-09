#!/bin/sh
# 
# Copyright (c) 2011-2013 Baptiste Daroussin <bapt@FreeBSD.org>
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
poudriere bulk [options] [-a|-f file|cat/port ...]

Parameters:
    -a          -- Build the whole ports tree
    -f file     -- Get the list of ports to build from a file
    [ports...]  -- List of ports to build on the command line

Options:
    -B name     -- What buildname to use (must be unique, defaults to
                   YYYY-MM-DD_HH:MM:SS). Resuming a previous build will not
                   retry built/failed/skipped/ignored packages.
    -b branch   -- Branch to choose for fetching packages from official
                   repositories: valid options are: latest, quarterly,
                   release_*, or a url.
    -C          -- Clean only the packages listed on the command line or
                   -f file.  Implies -c for -a.
    -c          -- Clean all the previously built binary packages and logs.
    -F          -- Only fetch from original master_site (skip FreeBSD mirrors)
    -H          -- Create a repository where the package filenames contain the
                   short hash of the contents.
    -I          -- Advanced Interactive mode. Leaves jail running with ports
                   installed after test.
    -i          -- Interactive mode. Enter jail for interactive testing and
                   automatically cleanup when done.
    -J n[:p]    -- Run n jobs in parallel, and optionally run a different
                   number of jobs in parallel while preparing the build.
                   (Defaults to the number of CPUs for n and 1.25 times n for p)
    -j name     -- Run only on the given jail
    -k          -- When doing testing with -t, don't consider failures as
                   fatal; don't skip dependent ports on findings.
    -N          -- Do not build package repository when build completed
    -NN         -- Do not commit package repository when build completed
    -n          -- Dry-run. Show what will be done, but do not build
                   any packages.
    -O overlays -- Specify extra ports trees to overlay
    -p tree     -- Specify on which ports tree the bulk build will be done
    -R          -- Clean RESTRICTED packages after building
    -r          -- Resursively test all dependencies as well
    -S          -- Don't recursively rebuild packages affected by other
                   packages requiring incremental rebuild. This can result
                   in broken packages if the ones updated do not retain
                   a stable ABI.
    -t          -- Test the specified ports for leftovers. Add -r to
                   recursively test all dependencies as well.
    -T          -- Try to build broken ports anyway
    -v          -- Be verbose; show more information. Use twice to enable
                   debug output
    -w          -- Save WRKDIR on failed builds
    -z set      -- Specify which SET to use
EOF
	exit ${EX_USAGE}
}

bulk_cleanup() {
	if [ -n "${CRASHED}" ]; then
		run_hook bulk crashed
	fi
}

PTNAME="default"
SETNAME=""
CLEAN=0
CLEAN_LISTED=0
DRY_RUN=0
ALL=0
BUILD_REPO=1
INTERACTIVE_MODE=0
OVERLAYS=""
COMMIT=1

if [ $# -eq 0 ]; then
	usage
fi

while getopts "ab:B:CcFf:HiIj:J:knNO:p:RrSTtvwz:" FLAG; do
	case "${FLAG}" in
		a)
			ALL=1
			;;
		B)
			BUILDNAME="${OPTARG}"
			;;
		b)
			PACKAGE_FETCH_BRANCH="${OPTARG}"
			validate_package_branch "${PACKAGE_FETCH_BRANCH}"
			;;
		c)
			CLEAN=1
			;;
		C)
			CLEAN_LISTED=1
			;;
		F)
			export MASTER_SITE_BACKUP=''
			;;
		f)
			# If this is a relative path, add in ${PWD} as
			# a cd / was done.
			if [ "${OPTARG#/}" = "${OPTARG}" ]; then
				OPTARG="${SAVED_PWD}/${OPTARG}"
			fi
			LISTPKGS="${LISTPKGS:+${LISTPKGS} }${OPTARG}"
			;;
		H)
			PKG_REPO_FLAGS="${PKG_REPO_FLAGS:+${PKG_REPO_FLAGS} }--hash --symlink"
			;;
		I)
			INTERACTIVE_MODE=2
			;;
		i)
			INTERACTIVE_MODE=1
			;;
		J)
			BUILD_PARALLEL_JOBS=${OPTARG%:*}
			PREPARE_PARALLEL_JOBS=${OPTARG#*:}
			;;
		j)
			jail_exists ${OPTARG} || err 1 "No such jail: ${OPTARG}"
			JAILNAME=${OPTARG}
			;;
		k)
			PORTTESTING_FATAL=no
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
		n)
			[ "${ATOMIC_PACKAGE_REPOSITORY}" = "yes" ] ||
			    err 1 "ATOMIC_PACKAGE_REPOSITORY required for dry-run support"
			DRY_RUN=1
			DRY_MODE="${COLOR_DRY_MODE}[Dry Run]${COLOR_RESET} "
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
		r)
			PORTTESTING_RECURSIVE=1
			;;
		S)
			SKIP_RECURSIVE_REBUILD=1
			;;
		T)
			export TRYBROKEN=yes
			;;
		t)
			PORTTESTING=1
			export NO_WARNING_PKG_INSTALL_EOL=yes
			export WARNING_WAIT=0
			export DEV_WARNING_WAIT=0
			;;
		R)
			NO_RESTRICTED=1
			;;
		v)
			VERBOSE=$((VERBOSE + 1))
			;;
		w)
			SAVE_WRKDIR=1
			;;
		z)
			[ -n "${OPTARG}" ] || err 1 "Empty set name"
			SETNAME="${OPTARG}"
			;;
		*)
			usage
			;;
	esac
done

if [ ${ALL} -eq 1 -a ${CLEAN_LISTED} -eq 1 ]; then
	CLEAN=1
	CLEAN_LISTED=0
fi

encode_args saved_argv "$@"
shift $((OPTIND-1))
post_getopts

if [ ${ALL} -eq 1 -a "${PORTTESTING}" -eq 1 ]; then
	PORTTESTING_FATAL=no
fi

: ${BUILD_PARALLEL_JOBS:=${PARALLEL_JOBS}}
: ${PREPARE_PARALLEL_JOBS:=$(echo "scale=0; ${PARALLEL_JOBS} * 1.25 / 1" | bc)}
PARALLEL_JOBS=${PREPARE_PARALLEL_JOBS}

if [ -z "${JAILNAME}" ]; then
	err 1 "Don't know on which jail to run please specify -j"
fi

maybe_run_queued "${saved_argv}"

MASTERNAME=${JAILNAME}-${PTNAME}${SETNAME:+-${SETNAME}}
_mastermnt MASTERMNT

export MASTERNAME
export MASTERMNT
export POUDRIERE_BUILD_TYPE=bulk

read_packages_from_params "$@"

CLEANUP_HOOK=bulk_cleanup

run_hook bulk start

jail_start "${JAILNAME}" "${PTNAME}" "${SETNAME}"

_log_path LOGD
if [ -d ${LOGD} -a ${CLEAN} -eq 1 ]; then
	msg "Cleaning up old logs in ${LOGD}"
	if [ ${DRY_RUN} -eq 0 ]; then
		rm -Rf ${LOGD} 2>/dev/null
	fi
fi

prepare_ports
if [ "${DRY_RUN}" -eq 0 ]; then
	show_build_summary
fi
show_dry_run_summary
markfs prepkg ${MASTERMNT}

PARALLEL_JOBS=${BUILD_PARALLEL_JOBS}

bset status "building:"

parallel_build ${JAILNAME} ${PTNAME} ${SETNAME}

_bget nbbuilt stats_built
_bget nbfailed stats_failed
_bget nbskipped stats_skipped
_bget nbignored stats_ignored
_bget nbfetched stats_fetched

if [ "${NO_RESTRICTED}" != "no" ]; then
	clean_restricted
fi

if [ ${BUILD_REPO} -eq 1 ]; then
	build_repo
fi

commit_packages

set +e

show_build_results

run_hook bulk done ${nbbuilt} ${nbfailed} ${nbignored} ${nbskipped} ${nbfetched}

if [ ${INTERACTIVE_MODE} -gt 0 ]; then
	enter_interactive
fi

bset status "done:"

exit $((nbfailed + nbskipped))
