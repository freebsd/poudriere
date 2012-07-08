#ifndef _POUDRIERE_H
#define _POUDRIERE_H
struct poudriere_conf {
	char *basefs;
	char *zfs_pool;
	char *freebsd_host;
	char *wrkdirprefix;
	char *resolv_conf;
	char *csup_host;
	char *svn_host;
	int use_tmpfs;
	int check_options_changed;
	char *makeworld_args;
};

extern struct poudriere_conf conf;

void parse_config(const char *);
#endif
