THISDIR=$(realpath $(dirname $0))
CMD=$(basename $0)
POUDRIEREPATH=$(realpath ${THISDIR}/../src/bin/poudriere)
POUDRIEREPREFIX=${POUDRIEREPATH%\/bin/*}
SCRIPTPREFIX=${POUDRIEREPREFIX}/share/poudriere

SCRIPTPATH="${SCRIPTPREFIX}/${CMD}"
POUDRIERE_ETC=${THISDIR}/etc

LIBEXECPREFIX="${POUDRIEREPATH%src/bin/poudriere}"
export PATH=${LIBEXECPREFIX}:${PATH}:/sbin:/usr/sbin

: ${DISTFILES_CACHE:=$(mktemp -dt distfiles)}
: ${BASEFS:=${POUDRIERE_ETC}}

mkdir -p ${POUDRIERE_ETC}/poudriere.d
cat > ${POUDRIERE_ETC}/poudriere.conf << EOF
NO_ZFS=yes
BASEFS=${BASEFS}
DISTFILES_CACHE=${DISTFILES_CACHE}
USE_TMPFS=all
USE_PROCFS=no
USE_FDESCFS=no
NOLINUX=yes
${FLAVOR_DEFAULT_ALL:+FLAVOR_DEFAULT_ALL=${FLAVOR_DEFAULT_ALL}}
${FLAVOR_ALL:+FLAVOR_ALL=${FLAVOR_ALL}}
EOF

: ${VERBOSE:=1}
: ${PARALLEL_JOBS:=2}

msg() {
	echo "$@"
}
msg_debug() {
	if [ ${VERBOSE} -le 1 ]; then
		msg_debug() { }
		return 0
	fi
	msg "[DEBUG] $@" >&2
}

msg_warn() {
	msg "[WARN] $@" >&2
}

msg_dev() {
	if [ ${VERBOSE} -le 2 ]; then
		msg_dev() { }
		return 0
	fi
	msg "[DEV] $@" >&2
}

assert() {
	[ $# -eq 3 ] || eargs assert expected actual msg
	local expected="$(echo "$1" | cat -ev)"
	local actual="$(echo "$2" | cat -ev)"
	local msg="$3"

	: ${EXITVAL:=0}

	EXITVAL=$((${EXITVAL:-0} + 1))

	if [ "${actual}" != "${expected}" ]; then
		aecho "${msg}: expected: '${expected}', actual: '${actual}'"
		exit ${EXITVAL}
	fi

	return 0

}

assert_not() {
	[ $# -eq 3 ] || eargs assert_not notexpected actual msg
	local notexpected="$(echo "$1" | cat -ev)"
	local actual="$(echo "$2" | cat -ev)"
	local msg="$3"

	: ${EXITVAL:=0}

	EXITVAL=$((${EXITVAL:-0} + 1))

	if [ "${actual}" = "${notexpected}" ]; then
		aecho "${msg}: notexpected: '${notexpected}', actual: '${actual}'"
		exit ${EXITVAL}
	fi

	return 0

}

assert_ret() {
	local expected="$1"
	local ret

	shift

	ret=0
	"$@" || ret=$?
	assert ${expected} ${ret} "$*"
}

aecho() {
	echo "$@" >&2
}
