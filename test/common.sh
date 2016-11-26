THISDIR=$(realpath $(dirname $0))
CMD=$(basename $0)
POUDRIEREPATH=$(realpath ${THISDIR}/../src)
POUDRIERE_ETC=${THISDIR}/etc
SCRIPTPREFIX=${POUDRIEREPATH}/share/poudriere
SCRIPTPATH="${SCRIPTPREFIX}/${CMD}.sh"

LIBEXECPREFIX=$(realpath ${POUDRIEREPATH}/..)
export PATH=${LIBEXECPREFIX}:${PATH}:/sbin:/usr/sbin

mkdir -p ${POUDRIERE_ETC}/poudriere.d
cat > ${POUDRIERE_ETC}/poudriere.conf << EOF
NO_ZFS=yes
BASEFS=${POUDRIERE_ETC}
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
msg_dev() {
	if [ ${VERBOSE} -le 2 ]; then
		msg_dev() { }
		return 0
	fi
	msg "[DEV] $@" >&2
}

assert() {
	[ $# -eq 3 ] || eargs assert expected actual msg
	local expected="$1"
	local actual="$2"
	local msg="$3"

	: ${EXITVAL:=0}

	EXITVAL=$((${EXITVAL:-0} + 1))

	if [ "${actual}" != "${expected}" ]; then
		aecho "${msg}: expected: '${expected}', actual: '${actual}'"
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

