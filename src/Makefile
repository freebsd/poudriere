PROG=	poudriere

SRCS=	parseconf.y \
	lexconf.l \
	poudriere.c \
	ports.c \
	jail.c \
	bulk.c \
	utils.c

LDADD=	-lsbuf -ljail

.include <bsd.prog.mk>
