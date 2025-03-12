#! /bin/sh
export LC_ALL=C
set -e

SH_DIR=$1
if [ -z "${SH_DIR}" ]; then
	echo "Usage: $0 /usr/src/bin/sh" >&2
	exit 1
fi
DESTDIR=external/sh
rm -rf "${DESTDIR}"
mkdir -p "${DESTDIR}"
DESTDIR_REAL="$(realpath "${DESTDIR}")"
ORIG_PWD="${PWD}"
cd "${SH_DIR}"
export WITHOUT_TESTS=yes
export WITHOUT_AUTO_OBJ=yes
make cleanobj
make clean cleandepend
make depend
paths=$(make -V '${.PATH:N.*bltin*}'|xargs realpath)
{
	echo builtins.def
	echo mkbuiltins
	echo mksyntax.c
	echo mknodes.c
	echo nodetypes
	echo nodes.c.pat
	echo mktokens
	for src in *.h $(make -V SRCS); do
		if [ -f "${src}" ]; then
			echo "${PWD}/${src}"
		else
			for p in ${paths}; do
				[ -f "${p}/${src}" ] && echo "${p}/${src}" && break
			done
		fi
	done
} | sort -u | \
    tar -c -T - \
    --exclude bltin \
    --exclude builtins.c \
    --exclude builtins.h \
    -s ",.*/,,g" -f - | tar -C "${DESTDIR_REAL}" -xf -
cp -R "${SH_DIR}/bltin" "${DESTDIR_REAL}/bltin"
make clean cleandepend
cd "${ORIG_PWD}"

# Fix backwards compat for st_mtim
sed -i '' -e 's,[[:<:]]st_mtim[[:>:]],st_mtimespec,g' "${DESTDIR}/test.c"
# Allow interaction with traps
sed -i '' -Ee 's,^static (char sigmode|char \*volatile trap|volatile sig_atomic_t gotsig),\1,' \
    "${DESTDIR}/trap.c"

git add -A "${DESTDIR}"
{
cat <<EOF
external/sh_compat/strchrnul.c
external/sh_compat/utimensat.c
EOF
find "${DESTDIR}" -name '*.c' -o -name '*.h' -o -name '*.def' -o -name 'mk*'
} | egrep -v "(mk(nodes|syntax)\.c|mktokens)" | sed -e 's,^,	,' | sort | \
{
	echo "sh_SOURCES="
	cat
} | sed -e '$ ! s,$, \\,' \
    > external/sh/Makefile.sources
git add -f external/sh/Makefile.sources
find -s external/patches/sh -type f -name '*.patch' | while read patch; do
	echo ">> Applying: ${patch}" >&2
	if ! git apply -v --index --directory=external "${patch}"; then
		echo "Failed applying patch ${patch}" >&2
		exit 1
	fi
done
