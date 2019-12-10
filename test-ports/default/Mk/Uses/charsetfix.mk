# $FreeBSD: head/Mk/Uses/charsetfix.mk 394503 2015-08-17 13:31:25Z mat $
#
# Lookup in Makefile.in to prevent a package from installing/modifying charset.alias
#
# Feature:	charsetfix
# Usage:	USES=charsetfix
# Valid ARGS:	does not require args
#
# MAINTAINER: portmgr@FreeBSD.org

.if !defined(_INCLUDE_USES_CHARSETFIX_MK)
_INCLUDE_USES_CHARSETFIX_MK=	yes

.if !empty(charsetfix_ARGS)
IGNORE=	USES=charsetfix does not require args
.endif

CHARSETFIX_MAKEFILEIN?=	Makefile.in

_USES_patch+=	600:charsetfix-post-patch
charsetfix-post-patch:
	@${FIND} ${WRKSRC} -name "${CHARSETFIX_MAKEFILEIN}" -type f | ${XARGS} ${REINPLACE_CMD} \
		-e 's|need_charset_alias=true|need_charset_alias=false|g ; \
		s|test -f $$(charset_alias)|false|g ;\
		s|test -f $$(DESTDIR)$$(libdir)/charset.alias|false|g'

.endif
