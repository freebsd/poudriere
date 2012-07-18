%option nounput
%option noinput
%option yylineno

%{
#include <string.h>
#include "parseconf.h"

static char *words(char *);

static char *
words(char *s)
{
	char *p;
	p = strrchr(s, '"');
	*p = '\0';
	p = s;
	p++;
	return p;
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

on|off			yylval.number =! strcmp(yytext, "on"); return STATE;
\"[^\"]*\"		yylval.string = strdup(words(yytext)); return WORDS;
[[:graph:]]+		yylval.string = strdup(yytext); return WORD;
[ \t]+			;
#.*$			yylineno--;
\n			;
%%
