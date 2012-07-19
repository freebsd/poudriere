#include <sys/types.h>
#include <sys/sbuf.h>
#include <sys/stat.h>
#include <sys/queue.h>
#include <sys/sysctl.h>
#include <sys/event.h>
#include <sys/time.h>

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
#include <ctype.h>
#include <fcntl.h>

#include "commands.h"
#include "utils.h"
#include "poudriere.h"

static STAILQ_HEAD(ports, port) ports = STAILQ_HEAD_INITIALIZER(ports);
struct port {
	char name[BUFSIZ];
	char origin[BUFSIZ];
	STAILQ_ENTRY(port) next;
};

struct dep {
	char origin[BUFSIZ];
	STAILQ_ENTRY(dep) next;
};

static STAILQ_HEAD(pkg_list, pkg) queue = STAILQ_HEAD_INITIALIZER(queue);

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
	struct port *p = NULL;

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

	STAILQ_FOREACH(p, &ports, next) {
		if (strcmp(p->origin, origin) == 0)
			break;
	}
	if (p == NULL) {
		snprintf(cmd, sizeof(cmd), "/usr/sbin/jexec -U root %s make -C /usr/ports/%s -VPKGNAME", j->name, origin);
		linecap = 0;
		line = NULL;
		if ((fp = popen(cmd, "r")) != NULL) {
			while (getline(&line, &linecap, fp) > 0) {
				p = calloc(0, sizeof(struct port));
				strlcpy(p->origin, origin, sizeof(p->origin));
				strlcpy(p->name, line, sizeof(p->name));
				if (p->name[strlen(p->name) - 1] == '\n')
					p->name[strlen(p->name) - 1] = '\0';
				break;
			}
			fclose(fp);
		}
	}

	/* TODO a problem occured, handle this later */
	if (p == NULL)
		return;

	strlcpy(myname, strrchr(path, '/') + 1, sizeof(myname));
	buf = myname;
	buf = strrchr(myname, '.');
	buf[0] = '\0';
	if (strcmp(myname, p->name) != 0) {
		printf("\t\t* %s is outdated\n", strrchr(path, '/') + 1);
		unlink(path);
		return;
	}
}

static int
compute_deps(struct pjail *j, struct pport_tree *p, const char *orig)
{
	struct stat st;
	struct port *port = NULL;
	struct pkg *pkg = NULL;
	struct dep *dep = NULL;
	char path[MAXPATHLEN];
	char cmd[BUFSIZ];
	char *line = NULL;
	char *buf, *buffer;
	size_t next;
	size_t linecap = 0;
	char *pkgname = NULL;
	int nbel, i;
	FILE *fp;

	STAILQ_FOREACH(pkg, &queue, next) {
		if (strcmp(pkg->origin, orig) == 0)
			return(0);
	}

	snprintf(path, sizeof(path), "%s/ports/%s", p->mountpoint, orig);

	if ((stat(path, &st) == -1) || !S_ISDIR(st.st_mode)) {
		warn("No such port %s in ports tree %s" , orig, p->name);
		return (-1);
	}

	pkg = malloc(sizeof(struct pkg));
	STAILQ_INIT(&pkg->deps);
	port = malloc(sizeof(struct port));
	strlcpy(port->origin, orig, sizeof(port->origin));
	strlcpy(pkg->origin, orig, sizeof(pkg->origin));
	STAILQ_INSERT_TAIL(&queue, pkg, next);
	snprintf(cmd, sizeof(cmd), "/usr/sbin/jexec -U root %s "
	    "make -C /usr/ports/%s "
	    "-VPKGNAME "
	    "-VPKG_DEPENDS "
	    "-VBUILD_DEPENDS "
	    "-VEXTRACT_DEPENDS "
	    "-VLIB_DEPENDS "
	    "-VPATCH_DEPENDS "
	    "-VFETCH_DEPENDS "
	    "-VRUN_DEPENDS",
	    j->name, orig);

	if ((fp = popen(cmd, "r")) != NULL) {
		while (getline(&line, &linecap, fp) > 0) {
			if (line[strlen(line) - 1] == '\n')
				line[strlen(line) - 1] = '\0';
			if (pkgname == NULL) {
				pkgname = line;
				strlcpy(port->name, pkgname, sizeof(port->name));
				STAILQ_INSERT_TAIL(&ports, port, next);
				continue;
			}
			if (line[0] == '\0')
				continue;
			nbel = split_chr(line, ' ');
			buf = buffer = line;
			for (i = 0; i < nbel; i++) {
				buf = buffer;
				next = strlen(buffer);
				STAILQ_FOREACH(dep, &pkg->deps, next) {
					if (strcmp(dep->origin, buf) == 0)
						break;
				}
				/* from the end find the previous : */
				buf = strrchr(buf, ':');
				if (strncmp(buf + 1, "/usr/ports/", 11) == 0) {
					buf += 11;
					buf[0] = '\0';
					buf++;
				} else {
					/* this is file:port:state */
					buf[0] = '\0';
					buf--;
					buf = strrchr(buf, ':');
					if (strncmp(buf + 1, "/usr/ports/", 11) == 0) {
						buf += 11;
						buf[0] = '\0';
						buf++;
					}
				}
				if (compute_deps(j, p, buf) != 0)
					return (-1);

				dep = malloc(sizeof(struct dep));
				strlcpy(dep->origin, buf, sizeof(dep->origin));
				STAILQ_INSERT_TAIL(&pkg->deps, dep, next);
				buffer += next + 1;
				i++;
			}
		}
		fclose(fp);
	}
	return (0);
}

int
queue_ports(struct pjail *j, struct pport_tree *p, const char *path)
{
	FILE *fp;
	size_t linecap = 0;
	char *line = NULL;
	char *buf;

	printf("====>> Calculating ports order and dependencies\n");

	if ((fp = fopen(path, "r")) == NULL) {
		warn("Enable to open %s:", path);
		return (-1);
	}

	while (getline(&line, &linecap, fp) > 0) {
		buf = line;
		while (isspace(buf[0]) && buf[0] != '\n')
			buf++;
		if (buf[0] == '#')
			continue;
		if (buf[strlen(buf) - 1] == '\n')
			buf[strlen(buf) - 1] = '\0';
		compute_deps(j, p, buf);
	}
	fclose (fp);
	return (0);

}

int
sanity_check(struct pjail *j)
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
jail_clone(struct pjail *j, int slot)
{
	char *argv[11];
	char mnt[MAXPATHLEN + 11];
	char snap[MAXPATHLEN];
	char fs[MAXPATHLEN];
	char buf[BUFSIZ];

	struct pjail *c;

	c = malloc(sizeof(struct pjail));

	struct zfs_query qj[] = {
		{ "poudriere:version", STRING, c->version, sizeof(c->version), 0 },
		{ "poudriere:arch", STRING, c->arch, sizeof(c->arch), 0 },
		{ "poudriere:stats_built", INTEGER, NULL, 0,  c->built },
		{ "poudriere:stats_failed", INTEGER, NULL, 0,  c->failed },
		{ "poudriere:stats_ignored", INTEGER, NULL, 0,  c->ignored },
		{ "poudriere:stats_queued", INTEGER, NULL, 0, c->queued },
		{ "poudriere:status", STRING, c->status, sizeof(c->status), 0 },
		{ "mountpoint", STRING, c->mountpoint, sizeof(c->mountpoint), 0 },
		{ "name", STRING, c->fs, sizeof(c->fs), 0 },
	};

	snprintf(mnt, sizeof(mnt), "mountpoint=%s/build/%d", j->mountpoint, slot);
	snprintf(c->name, sizeof(c->name), "%s-job-%i", j->name, slot);
	snprintf(snap, sizeof(snap), "%s@prepkg", j->fs);
	snprintf(fs, sizeof(fs), "%s/job-%d", j->fs, slot);

	argv[0] = "zfs";
	argv[1] = "clone";
	argv[2] = "-o";
	snprintf(buf, sizeof(buf), "poudriere:name=%s", c->name);
	argv[3] = buf;
	argv[4] = "-o";
	argv[5] = "poudriere:type=rootfs";
	argv[6] = "-o";
	argv[7] = mnt;
	argv[8] = snap;
	argv[9] = fs;
	argv[10] = NULL;

	if (exec("/sbin/zfs", argv) != 0) {
		warnx("Unable to clone %s", j->fs);
		free(c);
		return (-1);
	}
	if (!zfs_query("rootfs", c->name, qj, sizeof(qj) / sizeof(struct zfs_query)))
		errx(EX_USAGE, "No such jail %s", c->name);

	STAILQ_INSERT_TAIL(&j->children, c, next);
	return (0);
}

int
spawn_jobs(struct pjail *j, struct pport_tree *p)
{
	int i;
	size_t len;
	struct pjail *c;
	char *argv[4];
	char snap[MAXPATHLEN];

	/* if no parallel jobs number is defined then set it to hw.ncpu */
	if (conf.parallel_jobs == 0) {
		len = sizeof(conf.parallel_jobs);
		sysctlbyname("hw.ncpu", &conf.parallel_jobs, &len, NULL, 0);
	}

	printf("====>> Spawning %d builders\n", conf.parallel_jobs);

	snprintf(snap, sizeof(snap), "%s@prepkg", j->fs);
	argv[0] = "zfs";
	argv[1] = "snapshot";
	argv[2] = snap;
	argv[3] = NULL;

	if (exec("/sbin/zfs", argv) != 0)
		err(1, "Failed to snapshot to %s", snap);

	for (i = 0; i < conf.parallel_jobs; i++) {
		if (jail_clone(j, i) == 0) {
			c = STAILQ_LAST(&j->children, pjail, next);
			jail_start(c);
			mount_nullfs(c, p);
		}
	}

	return (0);
}

typedef enum {
	OK = 0,
	IGNORED,
	BROKEN,
	FETCH,
	CHECKSUM,
	EXTRACT,
	PATCH,
	CONFIGURE,
	BUILD,
	INSTALL,
	PACKAGE
} ebuild;

static struct phase {
	char *target;
	ebuild err;
} phase[] = {
	{ "fetch", FETCH },
	{ "checksum", CHECKSUM },
	{ "extract", EXTRACT },
	{ "patch", PATCH },
	{ "configure", CONFIGURE },
	{ "build", BUILD },
	{ "install", INSTALL },
	{ "package", PACKAGE },
	{ NULL, OK },
};

void
build(struct pjail *j)
{
	FILE *fp;
	char cmd[BUFSIZ];
	char *line = NULL;
	int linenb = 0;
	size_t linecap = 0;
	int i;
	char portdir[MAXPATHLEN];

	char *argv[9];

	printf("====>> Start building %s\n", j->pkg->origin);
	snprintf(cmd, sizeof(cmd), "/usr/sbin/jexec -U root %s "
	    "make -C /usr/ports/%s "
	    "-VIGNORED "
	    "-VBROKEN ", j->name, j->pkg->origin);

	if ((fp = popen(cmd, "r")) != NULL) {
		while (getline(&line, &linecap, fp) > 0) {
			linenb++;
			if (line[0] == '\n')
				continue;
			if (linenb == 1) {
				printf("====>> Marked as IGNORED, aborting: %s", line);
				exit(IGNORED);
			}
			if (linenb == 2)
				exit(BROKEN);
				printf("====>> Marked as BROKEN, aborting: %s", line);
		}
		fclose(fp);
	}

	snprintf(portdir, sizeof(portdir), "/usr/ports/%s", j->pkg->origin);

	for (i = 0; phase[i].target != NULL; i++) {
		if (phase[i].err == FETCH) {
			jail_kill(j);
			jail_run(j, true);
		}
		argv[0] = "jexec";
		argv[1] = "-U";
		argv[2] = "root";
		argv[3] = j->name;
		argv[4] = "make";
		argv[5] = "-C";
		argv[6] = portdir;
		argv[7] = phase[i].target;
		argv[8] = NULL;
		if (exec("/usr/sbin/jexec", argv) != 0)
			exit(phase[i].err);

		if (phase[i].err == CHECKSUM) {
			jail_kill(j);
			jail_run(j, true);
		}
	}

	exit(OK);
}

pid_t
build_pkg(struct pjail *j)
{
	int fd;
	pid_t pid;
	struct port *p;
	char logpath[MAXPATHLEN];

	switch ((pid = fork())) {
	case -1:
		return (-1);
	case 0:
		/* todo create it */
		STAILQ_FOREACH(p, &ports, next) {
			if (strcmp(p->origin, j->pkg->origin) == 0)
				break;
		}
		printf("%s\n",p->name);
		snprintf(logpath, sizeof(logpath), "%s/logs/%s-%s.log", conf.poudriere_data, j->name, p->name);
		fd = open(logpath, (O_CREAT|O_RDWR), 0644);
		dup2(fd, STDOUT_FILENO);
		dup2(fd, STDERR_FILENO);
		build(j);
		_exit(1);
		/* NOT REACHED */
	default:
		break;
	}

	signal(SIGCHLD, SIG_IGN);

	return (pid);
}

int
build_packages(struct pjail *j)
{
	int kq;
	struct kevent ke;
	struct kevent *e;
	int i = 0;
	struct pkg *p, *p2;
	struct dep *d;
	struct pjail *w, *w1;
	pid_t pid;
	int n;

	e = malloc(conf.parallel_jobs * sizeof(struct kevent));

	/* initialize the workers */
	STAILQ_FOREACH(w1, &j->children, next)
		w1->pkg = NULL;

	kq = kqueue();
	while (!STAILQ_EMPTY(&queue)) {
		STAILQ_FOREACH_SAFE(p, &queue, next, p2) {
			if (STAILQ_EMPTY(&p->deps)) {
				w = NULL;
				STAILQ_FOREACH(w1, &j->children, next) {
					if (w1->pkg == NULL) {
						w = w1;
						w->pkg = p;
						break;
					}
				}
				if (w == NULL)
					break;
				pid = build_pkg(w);
				EV_SET(&ke, pid, EVFILT_PROC, EV_ADD|EV_ONESHOT, NOTE_EXIT, 0, p);
				kevent(kq, &ke, 1, NULL, 0, NULL);
				STAILQ_REMOVE(&queue, p, pkg, next);
			}
		}
		n = kevent(kq, NULL, 0, e, conf.parallel_jobs, NULL);
		for (i = 0; i < n; i++) {
			p = (struct pkg *)e[i].udata;
			STAILQ_FOREACH(p2, &queue, next) {
				STAILQ_FOREACH(d, &p2->deps, next) {
					if (strcmp(d->origin, p->origin) == 0) {
						STAILQ_REMOVE(&p2->deps, d, dep, next);
						break;
					}
				}
			}
			/* release the builder */
			STAILQ_FOREACH(w1, &j->children, next) {
				if (w1->pkg == p)
					w1->pkg = NULL;
			}
			free(p);
		}
	}
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
	struct pkg *pkg;
	char snapshot[MAXPATHLEN], *args[4];

	STAILQ_INIT(&j.children);

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

	if (file == NULL) {
		usage_bulk();
		return (EX_USAGE);
	}

	strlcpy(j.name, jail, sizeof(j.name));
	strlcpy(p.name, porttree, sizeof(p.name));

	if (!zfs_query("rootfs", jail, qj, sizeof(qj) / sizeof(struct zfs_query)))
		errx(EX_USAGE, "No such jail %s", jail);

	if (!zfs_query("ports", porttree, qp, sizeof(qp) / sizeof(struct zfs_query)))
		errx(EX_USAGE, "No such ports tree %s", porttree);

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
	queue_ports(&j, &p, file);

	sanity_check(&j);

	spawn_jobs(&j, &p);

	build_packages(&j);

	jail_stop(&j);

	return (EX_OK);
}
