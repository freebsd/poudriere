#include <sys/types.h>
#include <sys/sbuf.h>
#include <sys/param.h>
#include <sys/jail.h>
#include <sys/mount.h>
#include <sys/linker.h>

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <jail.h>

#include "utils.h"
#include "poudriere.h"

static struct sbuf *
exec_buf(const char *cmd)
{
	FILE *fp;
	char buf[BUFSIZ];
	struct sbuf *res;

	if ((fp = popen(cmd, "r")) == NULL)
		return (NULL);

	res = sbuf_new_auto();
	while (fgets(buf, BUFSIZ, fp) != NULL)
		sbuf_cat(res, buf);

	pclose(fp);

	if (sbuf_len(res) == 0) {
		sbuf_delete(res);
		return (NULL);
	}

	sbuf_finish(res);

	return (res);
}

void
zfs_list(struct zfs_prop z[], const char *t, int n)
{
	struct sbuf *res, *cmd;
	char *walk, *end;
	const char *type;
	char **fields;
	int i=0;

	cmd = sbuf_new_auto();
	fields = malloc(n * sizeof(char *));

	sbuf_cat(cmd, "/sbin/zfs list -Hd1 -o poudriere:type");
	for (i = 0; i < n; i++)
		sbuf_printf(cmd, ",poudriere:%s", z[i].name);
	sbuf_printf(cmd, " %s/poudriere", conf.zfs_pool);
	sbuf_finish(cmd);
	for (i = 0; i < n; i++)
		printf(z[i].format, z[i].title);

	if ((res = exec_buf(sbuf_data(cmd))) != NULL) {
		walk = sbuf_data(res);
		end = walk + sbuf_len(res);
		type = walk;
		for (i = 0; i < n; i++)
			fields[i] = NULL;
		do {
			if (isspace(*walk)) {
				*walk = '\0';
				walk++;
				for (i = 0; i < n; i++) {
					if (fields[i] == NULL) {
						fields[i] = walk;
						break;
					}
				}
				if (i < n)
					continue;
				if (strcmp(type, t) == 0) {
					for (i = 0; i < n; i++)
						printf(z[i].format, fields[i]);
				}
				type = walk;
				for (i = 0; i < n; i++)
					fields[i] = NULL;
				continue;
			}
			walk++;
		} while (walk <= end);
		sbuf_delete(res);
	}
	free(fields);
	sbuf_delete(cmd);
}

int
zfs_query(const char *t, const char *n, struct zfs_query z[], int nfields)
{
	struct sbuf *res, *cmd;
	char *walk, *end;
	const char *type, *name;
	char **fields;
	int i = 0;
	int ret = 0;

	cmd = sbuf_new_auto();
	fields = malloc(nfields * sizeof(char *));

	sbuf_cat(cmd, "/sbin/zfs list -Hd1 -o poudriere:type,poudriere:name");
	for (i = 0; i < nfields; i++)
		sbuf_printf(cmd, ",%s", z[i].name);
	sbuf_printf(cmd, " %s/poudriere", conf.zfs_pool);
	sbuf_finish(cmd);

	if ((res = exec_buf(sbuf_data(cmd))) != NULL) {
		walk = sbuf_data(res);
		end = walk + sbuf_len(res);
		type = walk;
		name = NULL;
		for (i = 0; i < nfields; i++)
			fields[i] = NULL;
		do {
			if (isspace(*walk)) {
				*walk = '\0';
				walk++;
				if (name == NULL) {
					name = walk;
					continue;
				}
				for (i = 0; i < nfields; i++) {
					if (fields[i] == NULL) {
						fields[i] = walk;
						break;
					}
				}
				if (i < nfields)
					continue;
				if (strcmp(type, t) == 0 && strcmp(name, n) == 0) {
					for (i = 0; i < nfields; i++) {
						switch (z[i].type) {
						case STRING:
							strlcpy(z[i].strval, fields[i], z[i].strsize);
							break;
						case INTEGER:
							if (strcmp(fields[i], "-") == 0)
								z[i].intval = 0;
							else 
								z[i].intval = strtonum(fields[i], 0, INT_MAX, NULL);
							break;
						}
					}
					ret = 1;
					break;
				}
				type = walk;
				name = NULL;
				for (i = 0; i < nfields; i++)
					fields[i] = NULL;
				continue;
			}
			walk++;
		} while (walk <= end);
		sbuf_delete(res);
	}
	free(fields);
	sbuf_delete(cmd);

	return (ret);
}

int
jail_runs(const char *jailname)
{
	int jid;

	if ((jid = jail_getid(jailname)) < 0)
		return 0;

	return 1;
}

void
jail_stop(struct pjail *j)
{
	if (!jail_runs(j->name)) {
		fprintf(stderr, "====>> No such jail: %s\n", j->name);
		return;
	}
}

static const char *needfs[] = {
	"linprocfs",
	"linsysfs",
	"procfs",
	"nullfs",
	"xfs",
	NULL,
};

void
jail_start(struct pjail *j)
{
	int i;
	struct xvfsconf vfc;

	if (jail_runs(j->name)) {
		fprintf(stderr, "====>> jail %s is already running\n", j->name);
		return;
	}
	
	for (i = 0; needfs[i] != NULL; i++) {
		if (getvfsbyname(needfs[i], &vfc) < 0)
			if (kldload(needfs[i]) == -1) {
				fprintf(stderr, "failed to load %s\n", needfs[i]);
			}
	}
	if (conf.use_tmpfs) {
		if (getvfsbyname(needfs[i], &vfc) < 0)
			if (kldload(needfs[i]) == -1) {
				fprintf(stderr, "failed to load %s\n", needfs[i]);
			}
	}

	return;
}
