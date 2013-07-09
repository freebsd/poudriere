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

if [ $(find ${POUDRIERE_DATA}/build -mindepth 2 -maxdepth 2 2>&1 | wc -l) \
	-eq 0 ] ; then
	msg "No running builds"
	exit 0
fi

BUILDNAME=latest
POUDRIERE_BUILD_TYPE=bulk

if [ -n "${JAILNAME}" ]; then
	MASTERNAME=${JAILNAME}-${PTNAME}${SETNAME:+-${SETNAME}}
	MASTERMNT=${POUDRIERE_DATA}/build/${MASTERNAME}/ref
	jail_runs ${MASTERNAME} || err 1 "No such jail running"
	builders="$(bget builders 2>/dev/null || :)"

	JOBS="${builders}" siginfo_handler
else
	format="%-30s %-25s %6s %5s %6s %7s %7s %7s %7s\n"
	printf "${format}" "JAIL" "STATUS" "QUEUED" "BUILT" "FAILED" "SKIPPED" \
		"IGNORED" "TOBUILD"
	for mastermnt in ${POUDRIERE_DATA}/build/*/ref; do
		[ "${mastermnt}" = "${POUDRIERE_DATA}/build/*/ref" ] && break
		mastername=${mastermnt#${POUDRIERE_DATA}/build/}
		MASTERNAME=${mastername%/ref}

		status=$(bget status 2>/dev/null || :)
		nbqueued=$(bget stats_queued 2>/dev/null || :)
		nbfailed=$(bget stats_failed 2>/dev/null || :)
		nbignored=$(bget stats_ignored 2>/dev/null || :)
		nbskipped=$(bget stats_skipped 2>/dev/null || :)
		nbbuilt=$(bget stats_built 2>/dev/null || :)
		nbtobuild=$((nbqueued - (nbbuilt + nbfailed + nbskipped + nbignored)))
		printf "${format}" "${MASTERNAME}" "${status}" "${nbqueued}" \
			"${nbbuilt}" "${nbfailed}" "${nbskipped}" "${nbignored}" \
			"${nbtobuild}"
	done
fi
