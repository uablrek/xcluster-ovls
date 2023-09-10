/*
  SPDX-License-Identifier: Apache-2.0
  Copyright (c) 2022 Nordix Foundation
  From: https://github.com/Nordix/nfqueue-loadbalancer
*/

#include <log.h>
#include <stdarg.h>
#include <string.h>

static struct Logger default_logger;
Logger logger = &default_logger;

int logp(Logger logger, int level, const char *fmt, ...)
{
	if (level > logger->level)
		return 0;
	int rc = 0;
	va_list ap;
	va_start(ap, fmt);
	if (logger->logstr != NULL) {
		logger->logstr[0] = 0;
		if (level <= 3) {
			va_list aq;
			va_copy(aq, ap);
			rc = vsnprintf(logger->logstr, logger->logstrSize, fmt, aq);
			va_end(aq);
			// Remove tailing '\n'
			char* endp = strchr(logger->logstr, '\n');
			if (endp != NULL)
				*endp = 0;
		}
	}
	if (logger->logfile != NULL)
		rc = vfprintf(logger->logfile, fmt, ap);
	va_end(ap);
	return rc;	
}

__attribute__ ((__constructor__)) static void init(void) {
	default_logger.level = 6;
	default_logger.logfile = stderr;
	default_logger.logstr = NULL;
}
