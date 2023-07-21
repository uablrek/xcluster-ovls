# Xcluster/ovl - tserver

A test server image built on [Alpine Linux](https://www.alpinelinux.org/).
The image contains various test servers and tools for trouble shooting

Servers:

* [mconnect](https://github.com/Nordix/mconnect)
* [ctraffic](https://github.com/Nordix/ctraffic)
* [kahttp](https://github.com/Nordix/kahttp)
* [mini_httpd](http://acme.com/software/mini_httpd/)
* [sctpt](https://github.com/Nordix/xcluster/tree/master/ovl/sctp#the-sctpt-test-program)
* [telnetd](https://pkgs.alpinelinux.org/package/edge/main/x86_64/busybox-extras)

Start of server is controlled by the `SERVERS` environment
variable. Please check the manifest in [default/](
default/etc/kubernetes/tserver/tserver.yaml).


## Tests

```
./tserver.sh               # Help printout
./tserver.sh test > $log   # Run default test 
```
