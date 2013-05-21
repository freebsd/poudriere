/*
 * Copyright (c) 2013 David Demelier <demelier.david@gmail.com>
 *
 * Permission to use, copy, modify, and/or distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 */

/*
 * Parse 'make describe' output into the proper INDEX output
 */

#include <sys/types.h>
#include <sys/sbuf.h>
#include <sys/queue.h>
#include <sys/param.h>
#include <sys/jail.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include <err.h>
#include <jail.h>

/*
 * A field, it helps defining the list of fields such as depends
 * in the line. They are usually separated by spaces. We also
 * define a datatype FieldList which contains all fields.
 */
typedef struct Field Field;

struct Field {
	char		*value;
	STAILQ_ENTRY(Field) link;
};

typedef STAILQ_HEAD(, Field) FieldList;

/*
 * A port, has some fields and list of fields (such as depends). We also
 * define a datatype Ports which contains all ports listed in the
 * index.
 */
typedef struct Port Port;

struct Port {
	char		*name;
	char		*portpath;
	char		*prefix;
	char		*comment;
	char		*descfile;
	char		*maintainer;
	char		*categories;			/* A list but no need to split */
	char		*www;

	/* The following may be lists */
	FieldList	edepends;		/* extract deps */
	FieldList	pdepends;		/* patch depends */
	FieldList	fdepends;		/* fetch depends */
	FieldList	bdepends;		/* build depends */
	FieldList	rdepends;		/* run depends */

	STAILQ_ENTRY(Port) link;
};

typedef STAILQ_HEAD(, Port) Ports;

/*
 * Enumerate the index of some values in the index line. Documented
 * in the make describe target in ports/Mk/bsd.port.mk.
 */
typedef enum Value {
	ValueName	= 0,
	ValuePortPath,
	ValuePrefix,
	ValueComment,
	ValueDescription,
	ValueMaintainer,
	ValueCategories,
	ValueEDepends,
	ValuePDepends,
	ValueFDepends,
	ValueBDepends,
	ValueRDepends,
	ValueWWW,
	ValueLAST
} Value;

/* --------------------------------------------------------
 * Allocation helpers
 * -------------------------------------------------------- */

static void *
xmalloc(size_t size)
{
	void *ptr;

	if ((ptr = calloc(1, size)) == NULL)
		err(1, "malloc");

	return ptr;
}

static char *
xstrdup(const char *src)
{
	char *str;

	if ((str = strdup(src)) == NULL)
		err(1, "strdup");

	return str;
}

static void
usage(void)
{
	errx(1, "usage: %s oldindex newindex", getprogname());
}

/* --------------------------------------------------------
 * Field functions
 * -------------------------------------------------------- */

static Port * ports_find(const Ports *, const char *);

/*
 * Add the dependency only if not present. We will retrieve
 * the name of the port from the list
 */
static void
add_dep(FieldList *full, const Ports *ports, const Field *name)
{
	Port *port;
	Field *field, *n;
	bool found = false;	

	STAILQ_FOREACH(field, full, link)
		if (strcmp(field->value, name->value) == 0) {
			found = true;
			break;
		}

	if (!found) {
		port = ports_find(ports, name->value);
		n = xmalloc(sizeof (Field));
		n->value = xstrdup(port->portpath);
		STAILQ_INSERT_TAIL(full, n, link);
	}

}

/*
 * Split the list of dependencies by spaces and append it to the field
 * list.
 */
static void
field_list_fill(FieldList *fields, const char *line)
{
	char *word, *string, *tofree;
	Field *field;

	string = tofree = strdup(line);
	STAILQ_INIT(fields);

	if (strlen(line) > 0) {
		while ((word = strsep(&string, " \t")) != NULL) {
			if (strlen(word) > 0) {
				field		= xmalloc(sizeof (Field));
				field->value	= xstrdup(word);
				STAILQ_INSERT_TAIL(fields, field, link);
			}
		}
	}

	free(tofree);
}

/*
 * Prepare a list of dependencies to add, we also add the run depends of the
 * depends.
 */
static void
fields_list_catdeps(FieldList *full, const FieldList *deps, const Ports *ports)
{
	Field *field, *field2;
	Port *port;

	STAILQ_INIT(full);
	STAILQ_FOREACH(field, deps, link) {
		add_dep(full, ports, field);

		/* For that depend, find run depends of it */	
		port = ports_find(ports, field->value);

		STAILQ_FOREACH(field2, &port->rdepends, link)
			add_dep(full, ports, field2);
	}
}

/*
 * Free the list of fields.
 */
static void
fields_list_free(FieldList *fields)
{
	Field *field, *tmp;

	STAILQ_FOREACH_SAFE(field, fields, link, tmp) {
		free(field->value);
		free(field);
	}
}

/* --------------------------------------------------------
 * Ports functions
 * -------------------------------------------------------- */

/*
 * Split the line into the values separeted by '|'.
 */
static void
line_split(char *values[ValueLAST], const char *line)
{
	char *word, *string, *tofree;
	int i = 0;

	string = tofree = xstrdup(line);
	while ((word = strsep(&string, "|")) != NULL)
		values[i++] = xstrdup(word);

	free(tofree);
}

/*
 * Build a list of depends and write it to the depends.
 */
static void
buf_add_depends(struct sbuf *sbuf, const FieldList *fields, const Ports *ports,
    bool append_sep)
{
	Port *port;
	Field *field;
	FieldList depends;
	bool last;

	fields_list_catdeps(&depends, fields, ports);
	STAILQ_FOREACH(field, &depends, link) {
		last = STAILQ_LAST(&depends, Field, link) == field;
		port = ports_find(ports, field->value);
		sbuf_printf(sbuf, "%s%s", port->name, (last) ? "" : " ");
	}

	fields_list_free(&depends);
	if (append_sep)
		sbuf_putc(sbuf, '|');
}

/*
 * Add a port to the list, will split the line and extract information
 * to that port.
 */
static void
ports_add(Ports *ports, const char *line)
{
	Port *port;
	char *values[ValueLAST] = { NULL };

	line_split(values, line);
	
	/*
	 * Do not duplicate the values[] string because they were
	 * already strdup'ed() from the split_line function.
	 */
	port			= xmalloc(sizeof (Port));
	port->name		= values[ValueName];
	port->portpath		= values[ValuePortPath];
	port->prefix		= values[ValuePrefix];
	port->comment		= values[ValueComment];
	port->descfile		= values[ValueDescription];
	port->maintainer	= values[ValueMaintainer];
	port->categories	= values[ValueCategories];
	port->www		= values[ValueWWW];

	/*
	 * Split the following value to lists.
	 */
	field_list_fill(&port->edepends, values[ValueEDepends]);
	field_list_fill(&port->pdepends, values[ValuePDepends]);
	field_list_fill(&port->fdepends, values[ValueFDepends]);
	field_list_fill(&port->bdepends, values[ValueBDepends]);
	field_list_fill(&port->rdepends, values[ValueRDepends]);

	free(values[ValueEDepends]);
	free(values[ValuePDepends]);
	free(values[ValueFDepends]);
	free(values[ValueBDepends]);
	free(values[ValueRDepends]);

	STAILQ_INSERT_TAIL(ports, port, link);
}

/*
 * Find a port in the list by it's full path.
 */
static Port *
ports_find(const Ports *ports, const char *path)
{
	Port *port;

	STAILQ_FOREACH(port, ports, link)
		if (strcmp(port->portpath, path) == 0)
			return port;

	errx(1, "could not find dependency %s", path);
}

/*
 * Read the file specified by path and fill the port list.
 */
static void
ports_read(Ports *ports, const char *path)
{
	FILE *fp;
	char *line;
	size_t length;

	if ((fp = fopen(path, "r")) == NULL)
		err(1, "open: %s", path);

	STAILQ_INIT(ports);
	while ((line = fgetln(fp, &length)) != NULL && !feof(fp)) {
		if (length <= 0)
			err(1, "empty line, aborting");

		line[length - 1] = '\0';
		ports_add(ports, line);
	}

	fclose(fp);
}

/*
 * Write the new index to the file specified by path.
 */
static void
ports_write(const Ports *ports, const char *path)
{
	FILE *fp;
	struct sbuf *sbuf;
	Port *port;

	if ((fp = fopen(path, "w")) == NULL)
		err(1, "open");

	sbuf = sbuf_new_auto();

	STAILQ_FOREACH(port, ports, link) {
		sbuf_printf(sbuf, "%s|%s|%s|%s|%s|%s|%s|", port->name, port->portpath,
		    port->prefix, port->comment, port->descfile, port->maintainer,
		    port->categories);

		buf_add_depends(sbuf, &port->bdepends, ports, true);
		buf_add_depends(sbuf, &port->rdepends, ports, true);

		/* www is between dependencies */
		sbuf_printf(sbuf, "%s|", port->www);

		buf_add_depends(sbuf, &port->edepends, ports, true);
		buf_add_depends(sbuf, &port->pdepends, ports, true);
		buf_add_depends(sbuf, &port->fdepends, ports, false);

		/* Append that buffer */
		sbuf_finish(sbuf);
		fprintf(fp, "%s\n", sbuf_data(sbuf));
		sbuf_clear(sbuf);
	}

	fclose(fp);
	sbuf_delete(sbuf);
}

/*
 * Free the list of ports.
 */
static void
ports_free(Ports *ports)
{
	Port *port, *tmp;

	STAILQ_FOREACH_SAFE(port, ports, link, tmp) {
		free(port->name);
		free(port->portpath);
		free(port->prefix);
		free(port->comment);
		free(port->descfile);
		free(port->maintainer);
		free(port->categories);
		free(port->www);

		fields_list_free(&port->edepends);
		fields_list_free(&port->pdepends);
		fields_list_free(&port->fdepends);
		fields_list_free(&port->bdepends);
		fields_list_free(&port->rdepends);

		free(port);
	}
}

int
main(int argc, char **argv)
{
	Ports ports;
	int jid;
	const char *jail_str;

	if (argc < 4)
		usage();
		/* NOTREACHED */

	jail_str = argv[1];

	jid = jail_getid(jail_str);
	if (jid < 0)
		errx(1, "%s", jail_errmsg);

	if (jail_attach(jid) == -1)
		err(1, "jail_attach(%s)", jail_str);

	ports_read(&ports, argv[2]);
	ports_write(&ports, argv[3]);
	ports_free(&ports);

	return 0;
}
#include <stdio.h>
