%{
#include <sys/stat.h>
#include <sys/fcntl.h>

#include <err.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include "poudriere.h"

#define WANT_FILENAME 0
#define WANT_DIRNAME  1

int yyparse(void);
void yyerror(const char *, ...);
int yywrap(void);
FILE *yyin;

extern int yylineno;

void
yyerror(const char *fmt, ...)
{
	va_list ap;
	va_start(ap, fmt);
	printf(" at line %d\n", yylineno);
	va_end(ap);
	exit(EXIT_FAILURE);
}

int
yywrap(void)
{
	return 1;
}

int
word_is_fs(const char *word, int want)
{
	struct stat sb;

	if (stat(word, &sb) != 0) {
		yyerror("'%s': not a %s", word, want == WANT_DIRNAME ? "directory" : "file");
	}
	if (S_ISDIR(sb.st_mode) && want == WANT_DIRNAME)
		return (0);
	if (S_ISDIR(sb.st_mode) && want == WANT_FILENAME)
		return (0);
	yyerror("'%s': not a %s", word, want == WANT_DIRNAME ?  "directory" : "file");
	return (1);
}

void
parse_config(const char *filename)
{
	if ((yyin = fopen(filename, "r")) == NULL)
		err(EXIT_FAILURE, "%s", filename);

	yyparse();
	fclose(yyin);
}
%}

%{
int yylex(void);
%}

%token BASEFS ZFS_POOL FREEBSD_HOST WRKDIRPREFIX RESOLV_CONF CSUP_HOST
%token SVN_HOST USE_TMPFS CHECK_OPTIONS_CHANGED MAKEWORLD_ARGS
%token POUDRIERE_DATA SVN_PATH PARALLEL_JOBS

%union
{
	int number;
	char *string;
}
%token <number> STATE
%token <number> NUMBER
%token <string> WORD
%token <string> WORDS

%%
options: /* empty */
	| options option
	;

option: basefs | zfs_pool | freebsd_host | wrkdirprefix | resolv_conf
	| csup_host | svn_host | use_tmpfs | check_options_changed
	| makeworld_args | poudriere_data | svn_path | parallel_jobs ;

basefs: BASEFS WORD {
	if (word_is_fs($2, WANT_DIRNAME) != 0)
		YYERROR;
	conf.basefs = $2;
};

zfs_pool: ZFS_POOL WORD {
	conf.zfs_pool = $2;
};

parallel_jobs: PARALLEL_JOBS NUMBER { conf.parallel_jobs = $2; };

freebsd_host: FREEBSD_HOST WORD { conf.freebsd_host = $2; };

wrkdirprefix: WRKDIRPREFIX WORD {
	if (word_is_fs($2, WANT_DIRNAME) == 0)
		YYERROR;
	conf.wrkdirprefix = $2;
};

resolv_conf: RESOLV_CONF WORD {
	if (word_is_fs($2, WANT_FILENAME) == 0)
		YYERROR;
	conf.resolv_conf = $2;
};

csup_host: CSUP_HOST WORD { conf.csup_host = $2; };

svn_host: SVN_HOST WORD { conf.svn_host = $2; };

svn_path: SVN_PATH WORD {
	if (word_is_fs($2, WANT_FILENAME) != 0)
		YYERROR;
	conf.svn_path = $2;
};

use_tmpfs: USE_TMPFS STATE { conf.use_tmpfs = $2; };

check_options_changed: CHECK_OPTIONS_CHANGED STATE {
	conf.check_options_changed = $2;
};

makeworld_args: MAKEWORLD_ARGS WORD { conf.makeworld_args = $2; }
	| MAKEWORLD_ARGS WORDS { conf.makeworld_args = $2; };


poudriere_data: POUDRIERE_DATA WORD {
	if (word_is_fs($2, WANT_DIRNAME) != 0)
		YYERROR;
	conf.poudriere_data = $2;
};
%%
