set -e
set -u

TEST=$(realpath "$1")
: ${am_check:=0}
: ${am_installcheck:=0}

if [ "${am_check}" -eq 1 ] &&
	[ "${am_installcheck}" -eq 0 ]; then
	LIBEXECPREFIX="${abs_top_builddir}"
	export SCRIPTPREFIX="${abs_top_srcdir}/src/share/poudriere"
	export POUDRIEREPATH="poudriere"
	export PATH="${LIBEXECPREFIX}:${PATH}"
elif [ "${am_check}" -eq 1 ] &&
	[ "${am_installcheck}" -eq 1 ]; then
	LIBEXECPREFIX="${pkglibexecdir}"
	export SCRIPTPREFIX="${pkgdatadir}"
	#export POUDRIEREPATH="${bindir}/poudriere"
	export POUDRIEREPATH="poudriere"
	export PATH="${bindir}:${LIBEXECPREFIX}:${PATH}"
else
	if [ -z "${abs_top_srcdir-}" ]; then
		: ${VPATH:="$(realpath "${0%/*}")"}
		abs_top_srcdir="$(realpath "${VPATH}/..")"
		abs_top_builddir="${abs_top_srcdir}"
	fi
	LIBEXECPREFIX="${abs_top_builddir}"
	export SCRIPTPREFIX="${abs_top_srcdir}/src/share/poudriere"
	export POUDRIEREPATH="${abs_top_builddir}/poudriere"
	export PATH="${LIBEXECPREFIX}:${PATH}"
fi
if [ -z "${LIBEXECPREFIX-}" ]; then
	echo "ERROR: Could not determine POUDRIEREPATH" >&2
	exit 99
fi
: ${VPATH:=.}
: ${SH:=/bin/sh}
if [ "${SH}" = "sh" ]; then
	SH="${LIBEXECPREFIX}/sh"
fi

BUILD_DIR="${PWD}"
# source dir
THISDIR=${VPATH}
THISDIR="$(realpath "${THISDIR}")"
cd "${THISDIR}"

case "$1" in
bulk*.sh)
	: ${TIMEOUT:=3600}
	;;
esac
: ${TIMEOUT:=90}

[ -t 0 ] && export FORCE_COLORS=1
exec < /dev/null

# Need to trim environment of anything that may taint our top-level port var
# fetching.
while read var; do
	unset ${var}
done <<-EOF
$(env | egrep '^(WITH_|PORT|MAKE)'|grep -vF '.MAKE')
EOF

exec /usr/bin/timeout ${TIMEOUT} \
    "${LIBEXECPREFIX}/timestamp" \
    env \
    THISDIR="${THISDIR}" \
    SH="${SH}" \
    "${SH}" "${TEST}"
