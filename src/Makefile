PROG=	poudriere

CFLAGS+=	-O0 -ggdb 

SRCS=	parseconf.y \
	lexconf.l \
	poudriere.c \
	ports.c \
	jail.c \
	bulk.c \
	utils.c

LDADD=	-lsbuf -ljail -lutil

.include <bsd.prog.mk>
