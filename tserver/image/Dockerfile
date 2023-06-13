FROM alpine:latest
RUN apk add gcompat tcpdump jq iproute2 tcpdump nftables iptables ip6tables conntrack-tools busybox-extras mini_httpd strace curl
ADD --chown=0:0 ovl.tar /
CMD ["/init"]
