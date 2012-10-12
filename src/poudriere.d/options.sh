#!/bin/sh

# Copyright (c) 2012, Natacha Porté
#
# Permission to use, copy, modify, and distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

usage() {
	echo "poudriere options [parameters] [options]

Parameters:
    -f file     -- Give the list of ports to set options

Options:
    -j name     -- Run on the given jail
    -p tree     -- Specify on which ports tree the configuration will be done
    -n          -- Don't configure/show/remove options of dependicies
    -r          -- Remove port options instead of configuring them
    -s          -- Show port options instead of configuring them
    -z set      -- Specify which SET to use"

	exit 1
}

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`

PTNAME=default
SETNAME=""
DO_RECURSE=y
COMMAND=config-conditional
RECURSE_COMMAND=config-recursive

. ${SCRIPTPREFIX}/common.sh

[ $# -eq 0 ] && usage

while getopts "j:f:p:nrsz:" FLAG; do
	case "${FLAG}" in
		j)
			jail_exists ${OPTARG} || err 1 "No such jail"
			JAILNAME=${OPTARG}
			;;
		f)
			BULK_LIST=${OPTARG}
			;;
		p)
			PTNAME=${OPTARG}
			;;
		n)
			DO_RECURSE=
			;;
		r)
			COMMAND=rmconfig
			RECURSE_COMMAND=rmconfig-recursive
			;;
		s)
			COMMAND=showconfig
			RECURSE_COMMAND=showconfig-recursive
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

PORTSDIR=`port_get_base ${PTNAME}`
[ -d "${PORTSDIR}/ports" ] && PORTSDIR="${PORTSDIR}/ports"
[ -z "${PORTSDIR}" ] && err 1 "No such ports tree: ${PTNAME}"

if [ $# -eq 0 ]; then 
	[ -n "${BULK_LIST}" ] || err 1 "No packages specify"
	test -f ${BULK_LIST} || err 1 "No such list of packages: ${BULK_LIST}"
LISTPORTS=`grep -v -E '(^[[:space:]]*#|^[[:space:]]*$)' ${BULK_LIST}`
else
	[ -z "${BULK_LIST}" ] || err 1 "command line arguments and list of ports cannot be used at the same time"
	LISTPORTS="$@"
fi

PORT_DBDIR=${SCRIPTPREFIX}/../../etc/poudriere.d/${JAILNAME}${JAILNAME:+-}${SETNAME}${SETNAME:+-}options

mkdir -p ${PORT_DBDIR}

for origin in ${LISTPORTS}; do
	[ -d ${PORTSDIR}/${origin} ] || err 1 "No such ports ${origin}"
	make PORT_DBDIR=${PORT_DBDIR} \
		-C ${PORTSDIR}/${origin} \
		${COMMAND} \
		${DO_RECURSE:+${RECURSE_COMMAND}}
done
