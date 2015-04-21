#! /bin/sh
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
export MK_TESTS=no
make cleanobj
make clean cleandepend
make depend
paths=$(make -V '${.PATH:N.*bltin*}'|xargs realpath)
for src in *.h $(make -V SRCS); do
	if [ -f "${src}" ]; then
		echo "${PWD}/${src}"
	else
		for p in ${paths}; do
			[ -f "${p}/${src}" ] && echo "${p}/${src}" && break
		done
	fi
done | sort -u | tar -c -T - --exclude bltin -s ",.*/,,g" -f - | tar -C "${DESTDIR_REAL}" -xf -
cp -R "${SH_DIR}/bltin" "${DESTDIR_REAL}/bltin"
make clean cleandepend
cd "${ORIG_PWD}"

# Fix backwards compat for st_mtim
sed -i '' -e 's,st_mtim\.tv_sec,st_mtime,g' "${DESTDIR}/test.c"

git add -A "${DESTDIR}"
echo "sh_SOURCES= \\"
find "${DESTDIR}" -name '*.c'|sed -e 's,$, \\,'
