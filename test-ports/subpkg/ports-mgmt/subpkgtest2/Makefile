PORTNAME=	port-test2
PORTVERSION=	0.0.1
PORTREVISION=	1
CATEGORIES=	ports-mgmt
MASTER_SITES=
DISTFILES=
EXTRACT_ONLY=

MAINTAINER=	pizzamig@FreeBSD.org
COMMENT=	Meta port to test dependency of sub-packages
WWW=	https://asdf.asdf.de

NO_ARCH=	yes
NO_BUILD=	yes

OPTIONS_DEFINE=	DATA DOCS
OPTIONS_DEFAULT= DATA DOCS

RUN_DEPENDS=	${LOCALBASE}/bin/cmd1:ports-mgmt/subpkgtest \
				port-test-cmd2>=0.0.2:ports-mgmt/subpkgtest~cmd2

USES=	metaport
PLIST_FILES=	bin/link-cmd1 \
				bin/link-cmd2

SUBPACKAGES=	pciids
RUN_DEPENDS.pciids=	pciids>0:misc/pciids
DATA_SUBPACKAGES=	data
RUN_DEPENDS.data=	${LOCALBASE}/share/port-test/data1.txt:ports-mgmt/subpkgtest~data1
DOCS_SUBPACKAGES=	docs
RUN_DEPENDS.docs=	${LOCALBASE}/share/doc/port-test/README.md:ports-mgmt/subpkgtest~docs

do-install:
	${MKDIR} ${STAGEDIR}${PREFIX}/bin
	${LN} -sf ${PREFIX}/bin/cmd1 ${STAGEDIR}${PREFIX}/bin/link-cmd1
	${LN} -sf ${PREFIX}/bin/cmd2 ${STAGEDIR}${PREFIX}/bin/link-cmd2

.include <bsd.port.mk>
