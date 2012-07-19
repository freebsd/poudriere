#ifndef _POUDRIERE_H
#define _POUDRIERE_H
#include <sys/param.h>
#include <sys/queue.h>
#include <stdbool.h>

struct poudriere_conf {
	char *basefs;
	char *zfs_pool;
	char *freebsd_host;
	char *wrkdirprefix;
	char *resolv_conf;
	char *csup_host;
	char *svn_host;
	char *svn_path;
	int parallel_jobs;
	int use_tmpfs;
	int check_options_changed;
	char *makeworld_args;
	char *poudriere_data;
	bool pkgng;
	char ext[4];
	char pkg_add[MAXPATHLEN];
	char pkg_delete[MAXPATHLEN];
};

extern struct poudriere_conf conf;

void parse_config(const char *);
#endif
