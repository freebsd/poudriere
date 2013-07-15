SUBDIR=		awk \
		html

NO_OBJ=		yes

PREFIX?=	/usr/local

FILESDIR=	${PREFIX}/share/poudriere
FILES=		bulk.sh \
		clean.sh \
		common.sh \
		daemon.sh \
		distclean.sh \
		jail.sh \
		options.sh \
		ports.sh \
		processonelog.sh \
		queue.sh \
		status.sh \
		testport.sh
FILESMODE=	${BINMODE}

beforeinstall:
	mkdir -p ${FILESDIR}

.include <bsd.prog.mk>
