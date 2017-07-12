# $FreeBSD: head/Mk/Uses/tk.mk 399010 2015-10-10 17:46:45Z bapt $
#
# vim: ts=8 noexpandtab
#

tcl_ARGS=	${tk_ARGS}

_TCLTK_PORT=	tk

.include "${USESDIR}/tcl.mk"
