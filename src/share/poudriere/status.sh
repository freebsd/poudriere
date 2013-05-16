#!/bin/sh
# 
# Copyright (c) 2013 Bryan Drewery <bdrewery@FreeBSD.org>
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
	echo "poudriere status [options]

Options:
    -j name     -- Run on the given jail
    -p tree     -- Specify on which ports tree the configuration will be done
    -z set      -- Specify which SET to use"

	exit 1
}

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`

PTNAME=default
SETNAME=""

. ${SCRIPTPREFIX}/common.sh

while getopts "j:p:z:" FLAG; do
	case "${FLAG}" in
		j)
			jail_exists ${OPTARG} || err 1 "No such jail"
			JAILNAME=${OPTARG}
			;;
		p)
			PTNAME=${OPTARG}
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

shift $((OPTIND-1))

if [ ${POUDRIERE_DATA}/build/*/ref = "${POUDRIERE_DATA}/build/*/ref" ]; then
	msg "No running builds"
	exit 0
fi

POUDRIERE_BUILD_TYPE=bulk
BUILDNAME=latest

if [ -n "${JAILNAME}" ]; then
	format="%3s %-15s %-40s\n"
	printf "${format}" "JOB" "PHASE" "PORT"
	mastername=${JAILNAME}-${PTNAME}${SETNAME:+-${SETNAME}}
	mastermnt=${POUDRIERE_DATA}/build/${MASTERNAME}/ref
	for job_id in $(MASTERNAME=$mastername bget builders); do
		status="$(MASTERNAME=$mastername bget ${job_id} status)"
		phase=${status%:*}
		port=${status#*:}
		printf "${format}" "${job_id}" "${phase}" "${port}"
	done
else
	format="%-20s %-25s %6s %5s %6s %7s %7s %s\n"
	printf "${format}" "JAIL" "STATUS" "QUEUED" "BUILT" "FAILED" "SKIPPED" \
		"IGNORED"
	for mastermnt in ${POUDRIERE_DATA}/build/*/ref; do
		[ "${mastermnt}" = "${POUDRIERE_DATA}/build/*/ref" ] && break
		mastername=${mastermnt#${POUDRIERE_DATA}/build/}
		mastername=${mastername%/ref}

		status=$(MASTERNAME=$mastername bget status)
		nbqueued=$(MASTERNAME=$mastername bget stats_queued)
		nbfailed=$(MASTERNAME=$mastername bget stats_failed)
		nbignored=$(MASTERNAME=$mastername bget stats_ignored)
		nbskipped=$(MASTERNAME=$mastername bget stats_skipped)
		nbbuilt=$(MASTERNAME=$mastername bget stats_built)
		printf "${format}" "${mastername}" "${status}" "${nbqueued}" \
			"${nbbuilt}" "${nbfailed}" "${nbskipped}" "${nbignored}"
	done
fi
