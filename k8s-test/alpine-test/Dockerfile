FROM alpine:latest
RUN apk add libcap iproute2 jq && setcap 'cap_net_admin+eip' /sbin/ip
