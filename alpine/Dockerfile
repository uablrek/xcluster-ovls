FROM alpine:latest
RUN apk add gcompat jq iproute2 tcpdump nftables iptables ip6tables conntrack-tools busybox-extras strace curl inetutils-telnet nmap-ncat
CMD ["/bin/tail", "-f", "/dev/null"]
