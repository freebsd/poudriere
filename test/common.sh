THISDIR=$(realpath $(dirname $0))
CMD=$(basename $0)
POUDRIEREPATH=$(realpath $(which poudriere))
if [ -n "${VPATH}" ]; then
	POUDRIEREPREFIX="${VPATH}/../src"
	POUDRIEREPREFIX="$(realpath "${POUDRIEREPREFIX}")"
else
	POUDRIEREPREFIX="${POUDRIEREPATH%/poudriere}/src"
fi
SCRIPTPREFIX="${POUDRIEREPREFIX}/share/poudriere"

SCRIPTPATH="${SCRIPTPREFIX}/${CMD}"

LIBEXECPREFIX="${POUDRIEREPATH%/poudriere}"
POUDRIERE_ETC=${LIBEXECPREFIX}/test/etc

: ${DISTFILES_CACHE:=$(mktemp -dt distfiles)}
: ${BASEFS:=${POUDRIERE_ETC}}

mkdir -p ${POUDRIERE_ETC}/poudriere.d ${POUDRIERE_ETC}/run
ptmp=$(TMPDIR="${POUDRIERE_ETC}" mktemp -t poudriere_conf)
cat > "${ptmp}" << EOF
NO_ZFS=yes
BASEFS=${BASEFS}
DISTFILES_CACHE=${DISTFILES_CACHE}
USE_TMPFS=all
USE_PROCFS=no
USE_FDESCFS=no
NOLINUX=yes
# jail -c options
NO_LIB32=yes
NO_SRC=yes
SHARED_LOCK_DIR="${POUDRIERE_ETC}/run"
EOF
if ! cmp -s "${POUDRIERE_ETC}/poudriere.conf" "${ptmp}"; then
	mv -f "${ptmp}" "${POUDRIERE_ETC}/poudriere.conf"
else
	rm -f "${ptmp}"
fi
cat > "${POUDRIERE_ETC}/poudriere.d/make.conf" << EOF
DEFAULT_VERSIONS+=perl5=5.24
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
