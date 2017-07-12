# $FreeBSD: head/Mk/Uses/desthack.mk 369465 2014-09-28 16:36:31Z tijl $
#
# Handle gnu configure that does not properly support DESTDIR
#
# Feature:	desthack
# Usage:	USES=desthack
# Valid ARGS:	none
#
# MAINTAINER:	portmgr@FreeBSD.org

.if !defined(_INCLUDE_USES_DESTHACK_MK)
_INCLUDE_USES_DESTHACK_MK=	yes

.if !empty(desthack_ARGS)
IGNORE=	USES=desthack does not require args
.endif

GNU_CONFIGURE_PREFIX=	\$${${DESTDIRNAME}}${PREFIX}
GNU_CONFIGURE_MANPREFIX=	\$${${DESTDIRNAME}}${MANPREFIX}
.endif
