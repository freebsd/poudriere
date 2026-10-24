PORTNAME=	inc-dep-flavor-consumer
DISTVERSION=	1.0
CATEGORIES=	misc
MASTER_SITES=	#
DISTFILES=	#

MAINTAINER=	test@FreeBSD.org
COMMENT=	Consumer whose dependency on a nonexistent FLAVOR can be toggled via make.conf, for incremental STRICT_DEPS tests

LICENSE=	BSD2CLAUSE

.if defined(ADD_BOGUS_FLAVOR_DEP)
RUN_DEPENDS+=	bar>0:misc/bar@bogus
.endif

NO_BUILD=	yes
NO_ARCH=	yes

do-install:
	@${DO_NADA}

.include <bsd.port.mk>
