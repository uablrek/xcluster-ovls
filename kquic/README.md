# Xcluster/ovl - kquic

This ovl test [Linux kernel quic](https://github.com/lxin/quic) (kquic)
in xcluster. To learn about quic, [this book](
https://github.com/bagder/http3-explained) is a good starting point.
There are drafts for [multi-path](
https://datatracker.ietf.org/doc/draft-ietf-quic-multipath/) and
[load-balancing](https://datatracker.ietf.org/doc/draft-ietf-quic-load-balancers/),
but afaik those are not considered in kquic.

Most tasks are done with the `./admin.sh` script.
```
./admin.sh        # Help printout
./admin.sh env    # Environment to use. Note the KQUIC setting
```


## Clone, patch and build

Prerequisite: the `xcluster` kernel must be built locally.

At the time of writing a [PR](https://github.com/lxin/quic/pull/18)
has to be applied to add IPv6 support in test programs.

```
export KQUIC=/tmp/tmp/$USER/quic
git clone --depth 1 https://github.com/lxin/quic.git $KQUIC
curl -L https://github.com/lxin/quic/pull/18.patch | patch -d $KQUIC -p1
./admin.sh kquic_build
```

## Run tests

```
./admin.sh test     # The CI test. Takes ~2m
```


## Patch the kernel to add the quic module

The documentation describes howto patch the kernel to include the quic
module, rather than to build the module out-of-tree.

```
export __tdir=/tmp/tmp/$USER
./admin.sh kernel_build
./admin.sh test --kbin=$__tdir/linux/bzImage --no_module
```
