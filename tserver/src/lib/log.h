#pragma once
/*
  SPDX-License-Identifier: Apache-2.0
  Copyright (c) 2022 Nordix Foundation
  Oliginal from: https://github.com/Nordix/nfqueue-loadbalancer

  SPDX-License-Identifier: MIT-0
  For modifications. 
*/

#include <stdio.h>

typedef struct Logger {
	int level;
	FILE* logfile;
	char* logstr;
	size_t logstrSize;
} *Logger;
extern Logger logger;

enum LogLevel {
	loglevel_error = 3,
	loglevel_info = 6,
	loglevel_debug = 7,
	loglevel_trace = 10,
};

// This should be a macro with a condition to avoid unnecessary
// computation of arguments
#define log(l, lvl, arg...) if(l->level >= lvl)logp(l,lvl,arg)

// Convenience macros that assumes the logger is named "logger"
#define error(arg...) log(logger, loglevel_error, arg)
#define info(arg...) log(logger, loglevel_info, arg)
#define debug(arg...) log(logger, loglevel_debug, arg)
#define trace(arg...) log(logger, loglevel_trace, arg)

int logp(Logger logger, int level, const char *fmt, ...)
	__attribute__ ((format (printf, 3, 4)));
