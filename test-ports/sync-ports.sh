#! /bin/sh

src="${1:?}"

syncdirs="Mk Templates Tools Keywords ports-mgmt/pkg"
topfiles="MOVED UIDs GIDs"

for dir in ${syncdirs}; do
	rsync -avH --del "${src}"/"${dir}"/ test-ports/default/"${dir}"/
	git add -fA test-ports/default/"${dir}"
done
for file in ${topfiles}; do
	cp -f "${src}"/"${file}" test-ports/default/
	git add test-ports/default/"${file}"
done
