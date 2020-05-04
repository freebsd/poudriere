#! /bin/sh
set -e
export __MAKE_CONF=/dev/null
export PORT_DBDIR=/dev/null

: ${SVN_URL:=https://svn.freebsd.org/ports/head}
: ${DESTDIR:=$(realpath "${0%/*}/default")}
cd "${DESTDIR}"
export PORTSDIR="${DESTDIR}"

if [ -f .svn_rev ]; then
	read SVN_REV < .svn_rev
fi
: ${SVN_REV:=$(svn info "${SVN_URL}" | grep 'Last Changed Rev' | sed -e 's,.*: ,,')}

py3=$(make -f Mk/bsd.port.mk -V PYTHON3_DEFAULT:S,.,,)
perl5=$(make -f Mk/bsd.port.mk -V PERL5_DEFAULT)

# Minimum for a partial tree (and their deps)
# Despite being 'dirs' it is paths.
DIRS="
GIDs
Keywords
MOVED
Mk
Templates
Tools
UIDs
devel/gettext
devel/gettext-runtime
devel/gettext-tools
lang/perl${perl5}
lang/python
lang/python2
lang/python27
lang/python3
lang/python${py3}
security/openssl
"

update_dir() {
	local dir="$1"

	echo "Fetching ${dir}" >&2
	git rm -rf "${dir}" || :
	rm -rf "${dir}"
	svn export "${SVN_URL}/${dir}" "${dir}" || return $?
	git add -f "${dir}"
	if [ -d "${dir}" ]; then
		find "${dir}" -name Makefile -exec git add -f {} +
	fi
}

get_deps() {
	local dir="$1"

	echo "Getting deps: ${dir}" >&2
	make -C "${dir}" \
		_PDEPS='${PKG_DEPENDS} ${EXTRACT_DEPENDS} ${PATCH_DEPENDS} ${FETCH_DEPENDS} ${BUILD_DEPENDS} ${LIB_DEPENDS} ${RUN_DEPENDS}' \
		-V '${_PDEPS:C,([^:]*):([^:]*):?.*,\2,:C,^${PORTSDIR}/,,:O:u}' |
		grep -v '^make:'
}

recurse_deps() {
	local port dep

	for port in "$@"; do
		[ -f "${port}/.deps" ] && continue
		get_deps "${port}"
		touch "${port}/.deps"
	done | tr ' ' '\n' | sort -u |
	(
		updated_dir=0
		while read dep; do
			[ -z "${dep}" ] && continue
			[ -e "${dep}/Makefile" ] && continue
			update_dir "${dep}" &&
				updated_dir=1
		done
		exit "${updated_dir}"
	) && {
		find . -name .deps -size 0 -delete
		return 0
	}
	recurse_deps_all
}

recurse_deps_all() {
	local allports

	allports=$(find . -type d -name '[a-z]*' -depth 1 | xargs -J % find % -type d -depth 1 | sed -e 's,^\./,,')
	recurse_deps ${allports}
}

git rm -rf .

for dir in ${DIRS}; do
	update_dir "${dir}"
done

recurse_deps_all

find -s . -type d -name '[a-z]*' -depth 1 | while read cat; do
	find -s "${cat}" -type d -depth 1 | sed -e "s,^${cat}/,SUBDIR += ," > \
		"${cat}/Makefile"
	git add -f "${cat}/Makefile"
	echo "SUBDIR += ${cat#*/}"
done > Makefile
git add -f Makefile

echo "${SVN_REV}" > .svn_rev
git add .svn_rev
