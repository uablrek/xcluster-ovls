# Xcluster/ovl - haproxy

Build and test [HAProxy](https://github.com/haproxy/haproxy/tree/master)


## Build

There doesn't seem to be a binary release, so clone and make:

```
git clone --depth 1 -b v2.8.0 https://github.com/haproxy/haproxy.git \
  $GOPATH/src/github.com/haproxy/haproxy
cd $GOPATH/src/github.com/haproxy/haproxy
make -j$(nproc) TARGET=linux-glibc USE_OPENSSL=1
# Or:
./haproxy.sh clone --haproxyver=v2.8.0
./haproxy.sh build
```

## Test

```
# Automatic
./haproxy.sh test
# Manual
./haproxy.sh test start
# On vm-221:
wget -q -O- http://192.168.2.201:8080/cgi-bin/info  # (repeat...)
# On host:
xc scalein 3
# (test...)
xc scaleout 3
# (test again...)
```

