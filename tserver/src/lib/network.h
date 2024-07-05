#pragma once
/*
  SPDX-License-Identifier: MIT-0
*/
#include <log.h>

#include <netdb.h>

// parseAddress Parses an IP address. The addess must be numeric and
// be in format "ip-address:port". Examples:
//   10.0.0.0:80, [10.0.0.0]:80, fd00::1:80, [fd00::1]:80
int parseAddress(
	Logger logger, char const* address, struct sockaddr_storage* sas);

// formatAddress Formats an IP address to a string. This is the
// reverse of parseAddress()
int formatAddress(
	Logger logger, struct sockaddr_storage* sas1, char* buf, size_t size);

// tcpServer Opens a TCP server socket.
int tcpServer(Logger logger, char const* address, int backlog);

// udpSocket Open an UDP socket and bind to the address
int udpSocket(Logger logger, char const* address);
