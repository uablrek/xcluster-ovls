/*
  SPDX-License-Identifier: MIT-0
*/

#include <network.h>
#include <netdb.h>
#include <string.h>
#include <arpa/inet.h>
#include <errno.h>
#include <unistd.h>

int parseAddress(
	Logger logger, char const* address, struct sockaddr_storage* sas)
{
	char a[128];
	strncpy(a, address, sizeof(a));

	// Get the port after the last ':'
	char* port = strrchr(a, ':');
	if (port == NULL) {
		error("Invalid address, no port: %s\n", address);
		return -1;
	}
	*port++ = 0;

	char* node = a;
	if (*node == '[') {
		// Discard backets
		node++;
		char* e = strchr(node, ']');
		if (e != NULL)
			*e = 0;
	}

	struct addrinfo hints = {0};
	hints.ai_flags = AI_NUMERICHOST|AI_NUMERICSERV;
	hints.ai_family = AF_UNSPEC;
	hints.ai_socktype = SOCK_STREAM;
	struct addrinfo* res;
	int rc = getaddrinfo(node, port, &hints, &res);
	if (rc != 0) {
		error("parseAddress: %s\n", gai_strerror(rc));
	} else {
		memcpy(sas, res->ai_addr, res->ai_addrlen);
	}
	freeaddrinfo(res);
	return rc;
}

int formatAddress(
	Logger logger, struct sockaddr_storage* sas, char* buf, size_t size)
{
	if (sas->ss_family != AF_INET && sas->ss_family != AF_INET6) {
		error("formatAddress: unknown family: %d\n", sas->ss_family);
		return -1;
	}
	if (size < (INET6_ADDRSTRLEN + 7)) {
		error("formatAddress: buffer too small, min %u\n", INET6_ADDRSTRLEN+7);
	}
	unsigned short port;
	char* endp;
	if (sas->ss_family == AF_INET) {
		struct sockaddr_in* sin = (struct sockaddr_in*)sas;
		if (inet_ntop(AF_INET, &sin->sin_addr, buf, size) == NULL) {
			error("formatAddress: %s\n", strerror(errno));
			return -1;
		}
		endp = strchr(buf, 0);
		port = htons(sin->sin_port);
	} else {
		// Use brackets, like "[fd00::1]:80"
		*buf = '[';
		struct sockaddr_in6* sin = (struct sockaddr_in6*)sas;
		if (inet_ntop(AF_INET6, &sin->sin6_addr, buf+1, size-1) == NULL) {
			error("formatAddress: %s\n", strerror(errno));
			return -1;
		}
		endp = strchr(buf, 0);
		*endp++ = ']';
		port = htons(sin->sin6_port);
	}
	sprintf(endp, ":%u", port);
	return 0;
}

int tcpServer(Logger logger, char const* address, int backlog)
{
	struct sockaddr_storage adr;
	if (parseAddress(logger, address, &adr) != 0) {
		return -1;
	}
	int sd = socket(adr.ss_family, SOCK_STREAM, 0);
	if (sd < 0) {
		error("tcpServer: socket: %s\n", strerror(errno));
		return -1;
	}
	socklen_t addrlen = adr.ss_family == AF_INET
		? sizeof(struct sockaddr_in):sizeof(struct sockaddr_in6);
	if (bind(sd, (struct sockaddr const*)&adr, addrlen) != 0) {
		error("tcpServer: bind: %s\n", strerror(errno));
		close(sd);
		return -1;
	}
	if (listen(sd, backlog) != 0) {
		error("tcpServer: listen: %s\n", strerror(errno));
		close(sd);
		return -1;
	}
	return sd;
}

