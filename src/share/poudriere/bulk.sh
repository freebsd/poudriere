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
    -c          -- Clean all the previously built binary packages and logs.
    -C          -- Clean only the packages listed on the command line or
                   -f file.  Implies -c for -a.
    -i          -- Interactive mode. Enter jail for interactive testing and
                   automatically cleanup when done.
    -I          -- Advanced Interactive mode. Leaves jail running with ports
                   installed after test.
    -n          -- Dry-run. Show what will be done, but do not build
                   any packages.
    -R          -- Clean RESTRICTED packages after building
    -t          -- Test the specified ports for leftovers. Add -r to
                   recursively test all dependencies as well.
    -r          -- Resursively test all dependencies as well
    -k          -- When doing testing with -t, don't consider failures as
                   fatal; don't skip dependent ports on findings.
    -T          -- Try to build broken ports anyway
    -F          -- Only fetch from original master_site (skip FreeBSD mirrors)
    -S          -- Don't recursively rebuild packages affected by other
                   packages requiring incremental rebuild. This can result
                   in broken packages if the ones updated do not retain
                   a stable ABI.
    -J n[:p]    -- Run n jobs in parallel, and optionally run a different
                   number of jobs in parallel while preparing the build.
                   (Defaults to the number of CPUs for n and 1.25 times n for p)
    -j name     -- Run only on the given jail
    -N          -- Do not build package repository when build completed
    -p tree     -- Specify on which ports tree the bulk build will be done
    -v          -- Be verbose; show more information. Use twice to enable
                   debug output
    -w          -- Save WRKDIR on failed builds
    -z set      -- Specify which SET to use
EOF
	exit 1
}

bulk_cleanup() {
	[ -n "${CRASHED}" ] && run_hook bulk crashed
}

PTNAME="default"
SKIP_RECURSIVE_REBUILD=0
SETNAME=""
CLEAN=0
CLEAN_LISTED=0
DRY_RUN=0
ALL=0
BUILD_REPO=1
INTERACTIVE_MODE=0
. ${SCRIPTPREFIX}/common.sh

[ $# -eq 0 ] && usage

while getopts "B:iIf:j:J:CcknNp:RFtrTSvwz:a" FLAG; do
	case "${FLAG}" in
		B)
			BUILDNAME="${OPTARG}"
			;;
		t)
			PORTTESTING=1
			export NO_WARNING_PKG_INSTALL_EOL=yes
			export WARNING_WAIT=0
			export DEV_WARNING_WAIT=0
			;;
		r)
			PORTTESTING_RECURSIVE=1
			;;
		k)
			PORTTESTING_FATAL=no
			;;
		T)
			export TRYBROKEN=yes
			;;
		c)
			CLEAN=1
			;;
		C)
			CLEAN_LISTED=1
			;;
		i)
			INTERACTIVE_MODE=1
			;;
		I)
			INTERACTIVE_MODE=2
			;;
		n)
			[ "${ATOMIC_PACKAGE_REPOSITORY}" = "yes" ] ||
			    err 1 "ATOMIC_PACKAGE_REPOSITORY required for dry-run support"
			DRY_RUN=1
			DRY_MODE="${COLOR_DRY_MODE}[Dry Run]${COLOR_RESET} "
			;;
		f)
			# If this is a relative path, add in ${PWD} as
			# a cd / was done.
			[ "${OPTARG#/}" = "${OPTARG}" ] && \
			    OPTARG="${SAVED_PWD}/${OPTARG}"
			LISTPKGS="${LISTPKGS} ${OPTARG}"
			;;
		F)
			export MASTER_SITE_BACKUP=''
			;;
		j)
			jail_exists ${OPTARG} || err 1 "No such jail: ${OPTARG}"
			JAILNAME=${OPTARG}
			;;
		J)
			BUILD_PARALLEL_JOBS=${OPTARG%:*}
			PREPARE_PARALLEL_JOBS=${OPTARG#*:}
			;;
		N)
			BUILD_REPO=0
			;;
		p)
			porttree_exists ${OPTARG} ||
			    err 2 "No such ports tree ${OPTARG}"
			PTNAME=${OPTARG}
			;;
		R)
			NO_RESTRICTED=1
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
		a)
			ALL=1
			;;
		v)
			VERBOSE=$((${VERBOSE} + 1))
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

saved_argv="$@"
shift $((OPTIND-1))
post_getopts

[ ${ALL} -eq 1 -a -n "${PORTTESTING}" ] && PORTTESTING_FATAL=no

: ${BUILD_PARALLEL_JOBS:=${PARALLEL_JOBS}}
: ${PREPARE_PARALLEL_JOBS:=$(echo "scale=0; ${PARALLEL_JOBS} * 1.25 / 1" | bc)}
PARALLEL_JOBS=${PREPARE_PARALLEL_JOBS}

test -z "${JAILNAME}" && err 1 "Don't know on which jail to run please specify -j"

maybe_run_queued "${saved_argv}"

MASTERNAME=${JAILNAME}-${PTNAME}${SETNAME:+-${SETNAME}}
_mastermnt MASTERMNT

export MASTERNAME
export MASTERMNT
export POUDRIERE_BUILD_TYPE=bulk

CLEANUP_HOOK=bulk_cleanup

read_packages_from_params "$@"

run_hook bulk start

jail_start ${JAILNAME} ${PTNAME} ${SETNAME}

_log_path LOGD
if [ -d ${LOGD} -a ${CLEAN} -eq 1 ]; then
	msg "Cleaning up old logs in ${LOGD}"
	[ ${DRY_RUN} -eq 0 ] && rm -Rf ${LOGD} 2>/dev/null
fi

prepare_ports
show_dry_run_summary
markfs prepkg ${MASTERMNT}

PARALLEL_JOBS=${BUILD_PARALLEL_JOBS}

bset status "building:"

parallel_build ${JAILNAME} ${PTNAME} ${SETNAME}

_bget nbbuilt stats_built
_bget nbfailed stats_failed
_bget nbskipped stats_skipped
_bget nbignored stats_ignored
# Always create repository if it is missing (but still respect -N)
if 	[ ! -f ${MASTERMNT}/packages/digests.txz -o \
	  ! -f ${MASTERMNT}/packages/packagesite.txz ]; then
	[ $nbbuilt -eq 0 -a ${BUILD_REPO} -eq 1 ] && 
		msg "No package built, but repository needs to be created"
	# This block mostly to avoid next
# Package all newly built ports
elif [ $nbbuilt -eq 0 ]; then
	msg "No package built, no need to update the repository"
	BUILD_REPO=0
fi

[ "${NO_RESTRICTED}" != "no" ] && clean_restricted

[ ${BUILD_REPO} -eq 1 ] && build_repo

commit_packages

show_build_results

run_hook bulk done ${nbbuilt} ${nbfailed} ${nbignored} ${nbskipped}

[ ${INTERACTIVE_MODE} -gt 0 ] && enter_interactive

bset status "done:"

set +e

exit $((nbfailed + nbskipped))
