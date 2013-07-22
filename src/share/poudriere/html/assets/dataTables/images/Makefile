NO_OBJ=		yes
PREFIX?=	/usr/local
FILESDIR=	${PREFIX}/share/poudriere/html/assets/dataTables/images
FILES=		back_disabled.png \
		back_enabled.png \
		back_enabled_hover.png \
		forward_disabled.png \
		forward_enabled.png \
		forward_enabled_hover.png \
		sort_asc.png \
		sort_asc_disabled.png \
		sort_both.png \
		sort_desc.png \
		sort_desc_disabled.png

beforeinstall:
	mkdir -p ${DESTDIR}${FILESDIR}

.include <bsd.prog.mk>
