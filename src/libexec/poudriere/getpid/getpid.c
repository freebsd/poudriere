#include <stdio.h>
#include <unistd.h>

int
main(int argc __unused, char *argv[] __unused)
{
	printf("%d\n", getppid());
	return (0);
}
