PREFIX?=	/usr/local

all: dirwatch make_index dirempty cpdup/cpdup

dirempty: dirempty.c
	${CC} -Wall -Werror ${CFLAGS} dirempty.c -o dirempty

dirwatch: dirwatch.c
	${CC} -Wall -Werror ${CFLAGS} dirwatch.c -o dirwatch

make_index: make_index.c
	${CC} -Wall -Werror ${CFLAGS} make_index.c -o make_index -lsbuf

cpdup/cpdup:
	${MAKE} -C ${.CURDIR}/cpdup

install: dirwatch make_index dirempty cpdup/cpdup
	mkdir -p ${DESTDIR}${PREFIX}/libexec/poudriere
	install -m 755 -o root -g wheel dirwatch \
	    ${DESTDIR}${PREFIX}/libexec/poudriere
	install -m 755 -o root -g wheel make_index \
	    ${DESTDIR}${PREFIX}/libexec/poudriere
	install -m 755 -o root -g wheel dirempty \
	    ${DESTDIR}${PREFIX}/libexec/poudriere
	install -m 755 -o root -g wheel cpdup/cpdup ${PREFIX}/libexec/poudriere

clean:
	${MAKE} -C ${.CURDIR}/cpdup clean
	rm -f dirwatch make_index dirempty
