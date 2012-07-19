%option nounput
%option noinput
%option yylineno

%{
#include <err.h>
#include <sys/param.h>
#include <stdlib.h>
#include <string.h>
#include "parseconf.h"

static char *words(char *);
static int parse_number(const char *);

static char *
words(char *s)
{
	char *p;

	p = strrchr(s, '"');
	*p = '\0';
	p = s;
	p++;

	return (p);
}

static int
parse_number(const char *buf)
{
	int i;
	const char *errstr;

	i = strtonum(buf, 0, INT_MAX, &errstr);
	if (errstr)
		errx(1, "Unknown number %s: %s", buf, errstr);

	return (i);
}
%}

%%
basefs			return BASEFS;
zfs_pool		return ZFS_POOL;
freebsd_host		return FREEBSD_HOST;
wrkdirprefix		return WRKDIRPREFIX;
resolv_conf		return RESOLV_CONF;
csup_host		return CSUP_HOST;
svn_host		return SVN_HOST;
use_tmpfs		return USE_TMPFS;
check_options_changed	return CHECK_OPTIONS_CHANGED;
makeworld_args		return MAKEWORLD_ARGS;
poudriere_data		return POUDRIERE_DATA;
svn_path		return SVN_PATH;
parallel_jobs		return PARALLEL_JOBS;

on|off			yylval.number =! strcmp(yytext, "on"); return STATE;
\"[^\"]*\"		yylval.string = strdup(words(yytext)); return WORDS;
[[:graph:]]+		yylval.string = strdup(yytext); return WORD;
[0-9]+			yylval.number = parse_number(yytext); return NUMBER;
[ \t]+			;
#.*$			yylineno--;
\n			;
%%
