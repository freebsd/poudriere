#include <sys/types.h>
#include <sys/sbuf.h>
#include <sys/stat.h>
#include <sys/queue.h>

#define _WITH_GETLINE
#include <stdio.h>
#include <stdbool.h>
#include <string.h>
#include <sysexits.h>
#include <unistd.h>
#include <err.h>
#include <glob.h>
#include <fts.h>
#include <stdlib.h>

#include "commands.h"
#include "utils.h"
#include "poudriere.h"

static TAILQ_HEAD(pcache_list, pcache) cache = TAILQ_HEAD_INITIALIZER(cache);
struct pcache {
	char name[BUFSIZ];
	char origin[BUFSIZ];
	TAILQ_ENTRY(pcache) next;
};

void
usage_bulk(void)
{
	fprintf(stderr, "usage: poudriere bulk parameters [options]\n\n");
	fprintf(stderr,"Parameters:\n");
	fprintf(stderr,"\t%-15s%s\n\n", "-f", "Give the list of ports to build");
	fprintf(stderr,"Options:\n");
	fprintf(stderr,"\t%-15s%s\n", "-k", "Keep the previous built binary packages");
	fprintf(stderr,"\t%-15s%s\n", "-t", "Add some testings to package building");
	fprintf(stderr,"\t%-15s%s\n", "-j", "Run only on the given jail");
	fprintf(stderr,"\t%-15s%s\n", "-p", "Specify on which ports tree the bulk will be done");
}

void
delete_ifold(struct pjail *j, const char *path)
{
	FILE *fp;
	char cmd[BUFSIZ];
	char origin[MAXPATHLEN];
	char myname[MAXPATHLEN];
	char ppath[MAXPATHLEN];
	char *buf;
	char *line = NULL;
	size_t linecap = 0;
	struct stat st;
	struct pcache *c = NULL;

	origin[0] = '\0';

	if (conf.pkgng)
		snprintf(cmd, sizeof(cmd), "pkg query -F \"%s\" \"%%o\"", path);
	else
		snprintf(cmd, sizeof(cmd), "pkg_info -qo \"%s\"", path);
	if ((fp = popen(cmd, "r")) != NULL) {
		while (getline(&line, &linecap, fp) > 0)
			strlcpy(origin, line, sizeof(origin));
		fclose(fp);
	}
	if (origin[strlen(origin) - 1] == '\n')
		origin[strlen(origin) - 1] = '\0';
	snprintf(ppath, sizeof(ppath), "%s/usr/ports/%s", j->mountpoint, origin);
	if (lstat(ppath, &st) == -1) {
		printf("\t\t* %s, doesn't not exist anymore\n", strrchr(path, '/') + 1);
		unlink(path);
		return;
	}

	TAILQ_FOREACH(c, &cache, next) {
		if (strcmp(c->origin, origin) == 0)
			break;
	}
	if (c == NULL) {
		snprintf(cmd, sizeof(cmd), "/usr/sbin/jexec -U root %s make -C /usr/ports/%s -VPKGNAME", j->name, origin);
		linecap = 0;
		line = NULL;
		if ((fp = popen(cmd, "r")) != NULL) {
			while (getline(&line, &linecap, fp) > 0) {
				c = malloc(sizeof(struct pcache));
				strlcpy(c->origin, origin, sizeof(c->origin));
				strlcpy(c->name, line, sizeof(c->name));
				if (c->name[strlen(c->name) - 1] == '\n')
					c->name[strlen(c->name) - 1] = '\0';
				break;
			}
			fclose(fp);
		}
	}

	/* TODO a problem occured, handle this later */
	if (c == NULL)
		return;

	strlcpy(myname, strrchr(path, '/') + 1, sizeof(myname));
	buf = myname;
	buf = strrchr(myname, '.');
	buf[0] = '\0';
	if (strcmp(myname, c->name) != 0) {
		printf("\t\t* %s is outdated\n", strrchr(path, '/') + 1);
		unlink(path);
		return;
	}
}

int
sanify_check(struct pjail *j)
{
	char query[MAXPATHLEN];
	glob_t g;
	int i = 0;
	FTS *fts;
	FTSENT *ent = NULL;
	char *pkgpath[2];
	char vlocal[BUFSIZ], vremote[BUFSIZ], origin[BUFSIZ];

	printf("====>> Sanity checking the repository:\n");
	printf("\t- Delete outdated packages:\n");

	snprintf(query, sizeof(query), "%s/usr/ports/packages/All/*.%s", j->mountpoint, conf.ext);
	if (glob(query, 0, NULL, &g) == 0) {
		for (i = 0; i < g.gl_matchc; i++)
			delete_ifold(j, g.gl_pathv[i]);
		globfree(&g);
	}
	printf("done\n");
	printf("\t- Removing stale symlinks:\n");
	snprintf(query, sizeof(query), "%s/usr/ports/packages", j->mountpoint);
	pkgpath[0] = query;
	pkgpath[1] = NULL;

	if ((fts = fts_open(pkgpath, FTS_LOGICAL, NULL)) != NULL) {
		while (( ent = fts_read(fts)) != NULL) {
			if (ent->fts_info != FTS_SLNONE)
				continue;
			printf("\t\t * %s\n", ent->fts_name);
			unlink(ent->fts_accpath);
		}
		fts_close(fts);
	}
	return (0);
}

int
check_pkgtools(struct pjail *j)
{
	struct sbuf *b;
	int state = 0;
	char *pos;
	char *walk, *end;

	printf("====>> build will use: ");
	b = injail_buf(j, "/usr/bin/make -C /usr/ports/ports-mgmt/poudriere -VWITH_PKGNG -VPKG_ADD -VPKG_DELETE");
	walk = sbuf_data(b);
	end = walk + sbuf_len(b);
	pos = walk;
	do {
		if (*walk == '\n') {
			*walk = '\0';
			switch (state) {
			case 0:
				conf.pkgng = false;
				if (strlen(pos) != 0)
					conf.pkgng = true;
				break;
			case 1:
				strlcpy(conf.pkg_add, pos, sizeof(conf.pkg_add));
				break;
			case 2:
				strlcpy(conf.pkg_delete, pos, sizeof(conf.pkg_delete));
			}
			state++;
			walk++;
			pos = walk;
			continue;
		}
		walk++;
	} while (walk <= end);

	strlcpy(conf.ext, conf.pkgng ? "txz" : "tbz", sizeof(conf.ext));
	printf("%s\n", conf.pkgng ? "pkgng" : "legacy pkg_*");

	return (0);
}

int
exec_bulk(int argc, char **argv)
{
	signed char ch;
	const char *file = NULL;
	bool keep = false;
	bool test = false;
	char *jail = NULL;
	char *porttree = "default";
	struct pjail j;
	struct pport_tree p;
	char snapshot[MAXPATHLEN], *args[4];

	struct zfs_query qj[] = {
		{ "poudriere:version", STRING, j.version, sizeof(j.version), 0 },
		{ "poudriere:arch", STRING, j.arch, sizeof(j.arch), 0 },
		{ "poudriere:stats_built", INTEGER, NULL, 0,  j.built },
		{ "poudriere:stats_failed", INTEGER, NULL, 0,  j.failed },
		{ "poudriere:stats_ignored", INTEGER, NULL, 0,  j.ignored },
		{ "poudriere:stats_queued", INTEGER, NULL, 0, j.queued },
		{ "poudriere:status", STRING, j.status, sizeof(j.status), 0 },
		{ "mountpoint", STRING, j.mountpoint, sizeof(j.mountpoint), 0 },
		{ "name", STRING, j.fs, sizeof(j.fs), 0 },
	};

	struct zfs_query qp[] = {
		{ "poudriere:method", STRING, p.method, sizeof(p.method), 0 },
		{ "mountpoint", STRING, p.mountpoint, sizeof(p.mountpoint), 0 },
		{ "name", STRING, p.fs, sizeof(p.fs), 0 },
	};

	while ((ch = getopt(argc, argv, "f:ktj:p:")) != -1) {
		switch (ch) {
		case 'f':
			file = optarg;
			break;
		case 'k':
			keep = true;
			break;
		case 't':
			test = true;
			break;
		case 'j':
			jail = optarg;
			break;
		case 'p':
			porttree = optarg;
			break;
		default:
			usage_bulk();
			return (EX_USAGE);
		}
	}

	argc -= optind;
	argv += optind;

	if (jail == NULL) {
		usage_bulk();
		return (EX_USAGE);
	}

	strlcpy(j.name, jail, sizeof(j.name));
	strlcpy(p.name, porttree, sizeof(p.name));

	if (!zfs_query("rootfs", jail, qj, sizeof(qj) / sizeof(struct zfs_query)))
		err(EX_USAGE, "No such jail %s", jail);

	if (!zfs_query("ports", porttree, qp, sizeof(qp) / sizeof(struct zfs_query)))
		err(EX_USAGE, "No such ports tree %s", porttree);

	snprintf(snapshot, sizeof(snapshot), "%s@clean", j.fs);
	args[0] = "zfs";
	args[1] = "rollback";
	args[2] = snapshot;
	args[3] = NULL;

	printf("====>> cleaning up the jail: ");
	if (exec("/sbin/zfs", args) != 0)
		err(1, "failed to rollback to %s", snapshot);
	printf("done\n");

	jail_start(&j);
	jail_setup(&j);
	mount_nullfs(&j, &p);
	check_pkgtools(&j);
	sanify_check(&j);
	jail_stop(&j);

	return (EX_OK);
}
