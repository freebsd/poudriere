NO_OBJ=		yes
PREFIX?=	/usr/local

FILES=		dependency_loop.awk \
		humanize.awk \
		json.awk \
		siginfo_buildtime.awk
FILESDIR=	${PREFIX}/share/poudriere/awk

beforeinstall:
	mkdir -p ${FILESDIR}

.include <bsd.prog.mk>
