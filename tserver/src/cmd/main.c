/*
   SPDX-License-Identifier: MIT-0
*/

#include <log.h>
#include <cmd.h>
#include <stdio.h>
#include <stdlib.h>

#ifndef VERSION
#define VERSION unknown
#endif

#define xstr(s) str(s)
#define str(s) #s
char const* const version = xstr(VERSION);

static int cmdVersion(int argc, char **argv)
{
	puts(version);
	return 0;
}

int main(int argc, char *argv[])
{
	setlinebuf(stdout);
	setlinebuf(stderr);
	addCmd("version", cmdVersion);
	
	return handleCmd("tserver", argc, argv);
}
