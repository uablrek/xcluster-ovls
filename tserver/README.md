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

## Links

* https://github.com/kubernetes/community/blob/master/contributors/devel/sig-testing/writing-good-e2e-tests.md
* https://www.kubernetes.dev/blog/2023/04/12/e2e-testing-best-practices-reloaded/
* https://github.com/kubernetes-sigs/kwok
* https://github.com/skywind3000/kcp/blob/master/README.en.md
