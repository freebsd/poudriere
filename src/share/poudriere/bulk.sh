#!/bin/sh
# 
# Copyright (c) 2011-2013 Baptiste Daroussin <bapt@FreeBSD.org>
# Copyright (c) 2012-2013 Bryan Drewery <bdrewery@FreeBSD.org>
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
set -e

usage() {
	cat << EOF
poudriere bulk [options] [-f file|cat/port ...]

Parameters:
    -a          -- Build the whole ports tree
    -f file     -- Get the list of ports to build from a file
    [ports...]  -- List of ports to build on the command line

Options:
    -B name     -- What buildname to use (must be unique, defaults to
                   YYYY-MM-DD_HH:MM:SS)
    -c          -- Clean all the previously built binary packages
    -C          -- Clean only the packages listed on the command line or
                   -f file
    -R          -- Clean RESTRICTED packages after building
    -t          -- Test the specified ports for leftovers
    -r          -- Resursively test all dependencies as well
    -T          -- Try to build broken ports anyway
    -F          -- Only fetch from original master_site (skip FreeBSD mirrors)
    -s          -- Skip sanity checks
    -J n        -- Run n jobs in parallel (Defaults to the number of CPUs)
    -j name     -- Run only on the given jail
    -N          -- Do not build package repository or INDEX when build
                   completed
    -p tree     -- Specify on which ports tree the bulk build will be done
    -v          -- Be verbose; show more information. Use twice to enable
                   debug output
    -w          -- Save WRKDIR on failed builds
    -z set      -- Specify which SET to use
EOF
	exit 1
}

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
PTNAME="default"
SKIPSANITY=0
SETNAME=""
CLEAN=0
CLEAN_LISTED=0
ALL=0
BUILD_REPO=1
. ${SCRIPTPREFIX}/common.sh

[ $# -eq 0 ] && usage

while getopts "B:f:j:J:CcNp:RFtrTsvwz:a" FLAG; do
	case "${FLAG}" in
		B)
			BUILDNAME="${OPTARG}"
			;;
		t)
			PORTTESTING=1
			export DEVELOPER_MODE=yes
			;;
		r)
			PORTTESTING_RECURSIVE=1
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
		f)
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
			PARALLEL_JOBS=${OPTARG}
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
		s)
			SKIPSANITY=1
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
			VERBOSE=$((${VERBOSE:-0} + 1))
			;;
		*)
			usage
			;;
	esac
done

shift $((OPTIND-1))

test -z "${JAILNAME}" && err 1 "Don't know on which jail to run please specify -j"

MASTERNAME=${JAILNAME}-${PTNAME}${SETNAME:+-${SETNAME}}
MASTERMNT=${POUDRIERE_DATA}/build/${MASTERNAME}/ref

export MASTERNAME
export MASTERMNT
if [ ${CLEAN} -eq 1 ]; then
	msg_n "Cleaning previous bulks if any..."
	rm -rf ${POUDRIERE_DATA}/packages/${MASTERNAME}/*
	rm -rf ${POUDRIERE_DATA}/cache/${MASTERNAME}
	echo " done"
fi

export POUDRIERE_BUILD_TYPE=bulk

read_packages_from_params "$@"

run_hook bulk start

jail_start ${JAILNAME} ${PTNAME} ${SETNAME}

LOGD=`log_path`
if [ -d ${LOGD} -a ${CLEAN} -eq 1 ]; then
	msg "Cleaning up old logs"
	rm -f ${LOGD}/*.log 2>/dev/null
fi

prepare_ports

bset status "building:"

parallel_build ${JAILNAME} ${PTNAME} ${SETNAME}

bset status "done:"

failed=$(bget ports.failed | awk '{print $1 ":" $3 }' | xargs echo)
built=$(bget ports.built | awk '{print $1}' | xargs echo)
ignored=$(bget ports.ignored | awk '{print $1}' | xargs echo)
skipped=$(bget ports.skipped | awk '{print $1}' | sort -u | xargs echo)
nbfailed=$(bget stats_failed)
nbignored=$(bget stats_ignored)
nbskipped=$(bget stats_skipped)
nbbuilt=$(bget stats_built)
[ "$nbfailed" = "-" ] && nbfailed=0
[ "$nbignored" = "-" ] && nbignored=0
[ "$nbskipped" = "-" ] && nbskipped=0
[ "$nbbuilt" = "-" ] && nbbuilt=0
# Always create repository if it is missing (but still respect -T)
if [ $PKGNG -eq 1 ] && \
	[ ! -f ${MASTERMNT}/packages/digests.txz -o \
	  ! -f ${MASTERMNT}/packages/repo.txz ]; then
	[ $nbbuilt -eq 0 -a ${BUILD_REPO} -eq 1 ] && 
		msg "No package built, but repository needs to be created"
	# This block mostly to avoid next
# Package all newly built ports
elif [ $nbbuilt -eq 0 ]; then
	if [ $PKGNG -eq 1 ]; then
		msg "No package built, no need to update the repository"
	else
		msg "No package built, no need to update INDEX"
	fi
	BUILD_REPO=0
else
	[ "${NO_RESTRICTED:-no}" != "no" ] && clean_restricted
fi

[ ${BUILD_REPO} -eq 1 ] && build_repo

cleanup
if [ $nbbuilt -gt 0 ]; then
	msg_n "Built ports: "
	echo ${built}
	echo ""
fi
if [ $nbfailed -gt 0 ]; then
	msg_n "Failed ports: "
	echo ${failed}
	echo ""
fi
if [ $nbignored -gt 0 ]; then
	msg_n "Ignored ports: "
	echo ${ignored}
	echo ""
fi
if [ $nbskipped -gt 0 ]; then
	msg_n "Skipped ports: "
	echo ${skipped}
	echo ""
fi
run_hook bulk done ${nbbuilt} ${nbfailed} ${nbignored} ${nbskipped}
msg "[${MASTERNAME}] $nbbuilt packages built, $nbfailed failures, $nbignored ignored, $nbskipped skipped"
show_log_info

set +e

exit $((nbfailed + nbskipped))
