#! /bin/sh

THISDIR=$(realpath $(dirname $0))
cd "${THISDIR}"

if [ -z "${VPATH}" ]; then
	export PATH=..:${PATH}
fi

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

exec /usr/bin/timeout ${TIMEOUT} timestamp \
    ${SH:+env SH="${SH}"} ${SH:-sh} "$@"
