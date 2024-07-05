/*
  SPDX-License-Identifier: MIT-0
*/

#include <cmd.h>
#include <die.h>
#include <log.h>
#include <network.h>

#include <errno.h>
#include <string.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <pthread.h>
#include <stdint.h>
#include <unistd.h>
#include <sys/uio.h>
#include <sys/socket.h>
#include <poll.h>

// /usr/include/linux/netfilter_ipv4.h
#define SO_ORIGINAL_DST 80

static char const* reply = "Hello there";

static void* clientThread(void* arg) {
	int cd = (intptr_t)arg;
	debug("clientThread: cd=%d\n", cd);
	if (logger->level >= loglevel_debug) {
		struct sockaddr_storage sas;
		socklen_t len = sizeof(sas);
		int rc = getsockopt(cd, SOL_IP, SO_ORIGINAL_DST, (struct sockaddr*)&sas, &len);
		// TODO: Use getsockopt(fd, SOL_SOCKET, SO_DOMAIN,...)
		if (rc != 0 && errno == ENOENT) {
			debug("No SO_ORIGINAL_DST for IPv4, trying IPv6...\n");
			rc = getsockopt(cd, SOL_IPV6, SO_ORIGINAL_DST, (struct sockaddr*)&sas, &len);
		}
		if (rc == 0) {
			char buf[64];
			formatAddress(logger, &sas, buf, sizeof(buf));
			info("Original dest %s\n", buf);
		} else {
			error("getsockopt SO_ORIGINAL_DST: %s\n", strerror(errno));
		}
	}
	struct iovec iov[2];
	iov[0].iov_base = (void*)reply;
	iov[0].iov_len = strlen(reply);
	iov[1].iov_base = "\n";
	iov[1].iov_len = 1;
	size_t totalLen = strlen(reply) + 1;
	char buf[2048];
	while (read(cd, buf, sizeof(buf)) > 0) {
		if (writev(cd, iov, 2) != totalLen) {
			break;
		}
	}
	debug("clientThread: terminating\n");
	close(cd);
	return NULL;
}

static int cmdTcpServer(int argc, char **argv)
{
	char const* addrStr = NULL;
	char const* log_level = NULL;
	struct Option options[] = {
		{"help", NULL, 0,
		 "tcp-server\n"
		 "  A TCP server"},
		{"address", &addrStr, 1, "Bind address"},
		{"reply", &reply, 0, "Reply string"},
		{ "log-level", &log_level, 0, "Log level (0-7)"}, 
		{0, 0, 0, 0}
	};
	(void)parseOptionsOrDie(argc, argv, options);
	if (log_level != NULL)
		logger->level = atoi(log_level);

	int sd = tcpServer(logger, addrStr, 32);
	if (sd < 0)
		return -1;

	struct sockaddr_storage ca;
	socklen_t addrlen;
	pthread_attr_t attr;
	pthread_t tid;
	int cd;
	for (;;) {
		addrlen = sizeof(ca);
		cd = accept(sd, (struct sockaddr*)&ca, &addrlen);
		if (cd < 0)
			die("accept: %s\n", strerror(errno));
		if (logger->level >= loglevel_debug) {
			char buf[64];
			formatAddress(logger, &ca, buf, sizeof(buf));
			info("Accepted connect from %s\n", buf);
		}
		pthread_attr_init(&attr);
		pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
		if (pthread_create(&tid, &attr, clientThread, (void*)(intptr_t)cd) != 0)
			die("pthread_create failed\n");
		debug("Started client thread %lu\n", (unsigned long)tid);
	}
	return 0;
}

static int cmdUdpServer(int argc, char **argv)
{
	char const* addrStr = NULL;
	char const* log_level = NULL;
	struct Option options[] = {
		{"help", NULL, 0,
		 "udp-server\n"
		 "  A UDP server"},
		{"address", &addrStr, 1, "Bind address"},
		{ "log-level", &log_level, 0, "Log level (0-7)"}, 
		{0, 0, 0, 0}
	};
	(void)parseOptionsOrDie(argc, argv, options);
	if (log_level != NULL)
		logger->level = atoi(log_level);

	int sd = udpSocket(logger, addrStr);
	if (sd < 0)
		die("Failed to cerate server socket\n");

	char buf[32*1024];
	struct sockaddr_storage adr;
	ssize_t len;
	socklen_t alen;
	ssize_t sent;
	for (;;) {
		alen = sizeof(adr);
		len = recvfrom(
			sd, buf, sizeof(buf), 0, (struct sockaddr*)&adr, &alen);
		if (logger->level >= loglevel_debug) {
			char raddr[64];
			if (formatAddress(logger, &adr, raddr, sizeof(raddr)) == 0)
				debug("Received %lu bytes from %s\n", len, raddr);
		}
		sent = sendto(sd, buf, len, 0, (const struct sockaddr*)&adr, alen);
		if (sent != len) {
			if (sent < 0) {
				perror("send");
				return 1;
			} else
				error("Sent %lu bytes out of %lu\n", sent, len);
		}
	}
	return 0;
}

static int cmdUdpClient(int argc, char **argv)
{
	char const* addrStr = NULL;
	char const* log_level = NULL;
	char const* psize = NULL;	
	struct Option options[] = {
		{"help", NULL, 0,
		 "udp-client\n"
		 "  A UDP client"},
		{"address", &addrStr, 1, "Server address"},
		{"size", &psize, 0, "Packet size"},		
		{ "log-level", &log_level, 0, "Log level (0-7)"}, 
		{0, 0, 0, 0}
	};
	(void)parseOptionsOrDie(argc, argv, options);
	if (log_level != NULL)
		logger->level = atoi(log_level);

	int sd = udpSocket(logger, ":::0");
	if (sd < 0) {
		return -1;
	}

	struct sockaddr_storage adr;
	if (parseAddress(logger, addrStr, &adr) != 0)
		return -1;
	socklen_t alen = adr.ss_family == AF_INET
		? sizeof(struct sockaddr_in):sizeof(struct sockaddr_in6);
	
	char buf[32*1024];
	ssize_t len = 1024;
	if (psize != NULL) {
		len = atoi(psize);
		if (len < 0 || len > sizeof(buf))
			die("Size invalid %lu", len);
	}
	ssize_t sent = sendto(sd, buf, len, 0, (const struct sockaddr*)&adr, alen);
	if (sent != len) {
		if (sent < 0)
			perror("send");
		else
			error("Sent %lu bytes out of %lu\n", sent, len);
		return 1;
	}

	// Wait 1s for a response
	struct pollfd pfd = {sd, POLLIN, 0};
	if (poll(&pfd, 1, 1000) != 1)
		die("No response");
	debug("Got response\n");

	len = recvfrom(
		sd, buf, sizeof(buf), 0, (struct sockaddr*)&adr, &alen);
	if (sent != len) {
		if (len < 0) {
			perror("recvfrom");
			return 1;
		} else
			error("Sent %lu bytes out of %lu\n", sent, len);
	}
	char raddr[64];
	if (formatAddress(logger, &adr, raddr, sizeof(raddr)) == 0)
		info("Received %lu bytes from %s\n", len, raddr);
	return 0;
}


__attribute__ ((__constructor__)) static void addCommands(void) {
	addCmd("tcp-server", cmdTcpServer);
	addCmd("udp-server", cmdUdpServer);
	addCmd("udp-client", cmdUdpClient);
}
