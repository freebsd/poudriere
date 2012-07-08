#ifndef _UTILS_H
#define _UTILS_H

struct zfs_prop {
	const char *title;
	const char *name;
	const char *format;
};

void zfs_list(struct zfs_prop[], const char *, int);

#endif
