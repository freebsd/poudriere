#!/bin/sh
# 
# Copyright (c) 2010-2013 Baptiste Daroussin <bapt@FreeBSD.org>
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

LC_ALL=C
unset SHELL
SAVED_TERM=$TERM
unset TERM
POUDRIERE_VERSION="3.1-pre"

usage() {
	echo "Usage: poudriere [-e etcdir] command [options]

Commands:
    bulk        -- generate packages for given ports
    distclean   -- clean old distfiles
    daemon      -- launch the poudriere daemon
    help        -- show usage
    jail        -- manage the jails used by poudriere
    ports       -- create, update or delete the portstrees used by poudriere
    options     -- configure ports options
    queue       -- queue a build request
    status      -- get status of builds
    testport    -- launch a test on a given port
    version     -- show poudriere version"
	exit 1
}

SETX=""
while getopts "e:x" FLAG; do
        case "${FLAG}" in
		e)
			if [ ! -d "$OPTARG" ]; then
				echo "Error: argument '$OPTARG' not a directory"
				exit 1
			fi
			export POUDRIERE_ETC=$OPTARG
			;;
                x)
                        SETX="-x"
                        ;;
                *)
                        usage
                        ;;
        esac
done

shift $((OPTIND-1))

[ $# -lt 1 ] && usage

POUDRIEREPATH=`realpath $0`
POUDRIEREPREFIX=${POUDRIEREPATH%\/bin/*}
POUDRIEREPREFIX=${POUDRIEREPREFIX}/share/poudriere

CMD=$1
shift
CMD_ENV="PATH=${PATH} POUDRIERE_VERSION=${POUDRIERE_VERSION}"
[ -n "${POUDRIERE_ETC}" ] && CMD_ENV="${CMD_ENV} POUDRIERE_ETC=${POUDRIERE_ETC}"

# Handle special-case commands first.
case "${CMD}" in
	version)
		echo "${POUDRIERE_VERSION}"
		;;
	help)
		usage
		;;
	jails)
		CMD="jail"
		;;
	options|testport)
		CMD_ENV="${CMD_ENV} TERM=${SAVED_TERM}"
esac

case "${CMD}" in
	bulk|distclean|daemon|jail|ports|options|queue|status|testport)
		;;
	*)
		echo "Unknown command '${CMD}'"
		usage
		;;
esac

exec env -i ${CMD_ENV} /bin/sh ${SETX} "${POUDRIEREPREFIX}/${CMD}.sh" $@
