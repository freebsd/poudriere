#ifndef _UTILS_H
#define _UTILS_H

#include <sys/param.h>
#include <sys/queue.h>

#include <stdbool.h>

struct zfs_prop {
	const char *title;
	const char *name;
	const char *format;
};

typedef enum {
	STRING,
	INTEGER,
} zfs_query_type;

struct zfs_query {
	char *name;
	zfs_query_type type;
	char *strval;
	size_t strsize;
	int intval;
};

struct pjail {
	char name[20];
	char version[13];
	char arch[7];
	char mountpoint[MAXPATHLEN];
	char fs[MAXPATHLEN];
	int built;
	int failed;
	int ignored;
	int queued;
	char status[BUFSIZ];
	struct pkg *pkg;
	STAILQ_HEAD(jails, pjail) children;
	STAILQ_ENTRY(pjail) next;
};

struct pkg {
	char origin[BUFSIZ];
	STAILQ_HEAD(deps, dep) deps;
	STAILQ_ENTRY(pkg) next;
};

struct pport_tree {
	char name[20];
	char method[10];
	char mountpoint[MAXPATHLEN];
	char fs[MAXPATHLEN];
	struct pport_tree *next;
};

void zfs_list(struct zfs_prop[], const char *, int);
int jail_runs(const char *name);
int zfs_query(const char *, const char *, struct zfs_query[], int);
void jail_stop(struct pjail *j);
void jail_start(struct pjail *j);
void jail_setup(struct pjail *j);
void jail_kill(struct pjail *j);
void jail_run(struct pjail *j, bool network);
int exec(char *, char * const argv[]);
struct sbuf *injail_buf(struct pjail *j, char *cmd);
void mount_nullfs(struct pjail *j, struct pport_tree *p);
int split_chr(char *str, char sep);

#endif
