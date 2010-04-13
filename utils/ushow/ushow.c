/*
 * grab tt output from verilog simulator log file
 * brad@heeltoe.com
 *
 * as in, "cat verilog.log | ./ushow"
 *
 * displays tt output in a rational manner
 */

#include <stdio.h>

int c;
char b[1024];

void add(int v)
{
	b[c++] = v & 0x7f;
	b[c] = 0;
	printf("output: %s\n", b);
	fflush(stdout);
}

main()
{
	char line[1024];

	while (fgets(line, sizeof(line), stdin)) {
		if (memcmp(&line[4], "tx_data ", 8) == 0) {
			char s1[256], s2[256];
			int v;
			sscanf(line, "%s %s %o", s1, s2, &v);
			add(v);
		}
	}
}
