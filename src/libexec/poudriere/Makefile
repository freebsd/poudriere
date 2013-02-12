PREFIX?=	/usr/local

dirwatch: dirwatch.c
	${CC} -Wall -Werror ${CFLAGS} dirwatch.c -o dirwatch

All: dirwatch

install: dirwatch
	mkdir -p ${PREFIX}/libexec/poudriere
	install -m 755 -o root -g wheel dirwatch ${PREFIX}/libexec/poudriere

clean:
	rm -f dirwatch
