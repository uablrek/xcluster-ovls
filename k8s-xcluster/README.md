# Xcluster/ovl - k8s-xcluster

Describes how [xcluster](https://github.com/Nordix/xcluster) can be
used for advanced network testing with Kubernetes.

**Xcluster is not a Kubernetes test tool!**

It is primarily a *networking test tool* that can be used with
Kubernetes. For K8s development in general, there are far more
suitable environments like [KinD](https://kind.sigs.k8s.io/).

Xcluster makes it possible to test network features in virtual
environment that most other environments doesn't support, like:

* Easy switch between different CNI-plugins
* K8s HA setup
* SR-IOV without a supporting HW NIC (requires qemu 7)
* Different network topologies
* Test any kernel setup, e.g. kernel versions, config or eBPF

Below some features of `xcluster` are described, and then some practical
examples of network testing in K8s.


## Xcluster

An `xcluster` consists of `qemu` VMs sharing a base disk image. The
VMs get different roles, e.g. cluster nodes or routers, depending on
the host name.

### It's fast and lightweight

A 40-node K8s cluster started in less than 10s:

<img src="xcluster40.svg" width="50%" />


### Installation

The demo above was intended to catch your interrest. Here comes an
instruction howto run it on your own PC (Ubuntu Linux assumed).

First check the [dependencies](
https://github.com/Nordix/xcluster#execution-environment-and-dependencies),
then start without K8s:

```
xcver=8.0.0
cd /your/experiment/dir
curl -L https://github.com/Nordix/xcluster/releases/download/$xcver/xcluster-$xcver.tar.xz | tar -Jx
cd xcluster
. ./Envsettings
xc mkcdrom xnet
xc start     # 6 xterm consoles should pop up
xc stop
```

Please read [the troubleshooting document](
https://github.com/Nordix/xcluster/blob/master/doc/troubleshooting.md)
if needed.

Add k8s (continuation from above):
```
. ./Envsettings.k8s
# The printouts say that you have no k8s image. Load one:
armurl=http://artifactory.nordix.org/artifactory/cloud-native
curl -L $armurl/xcluster/images/hd-k8s-v1.28.2.img.xz | xz -d > $__image
xc mkcdrom   # clear ovl's
xc start     # 6 xterm consoles should pop up, but now with K8s
# $KUBECONFIG is set for you, but you must install "kubectl" yourself
# (or do this in any xcluster xterm)
kubectl get nodes
xc stop
```

**WARNING**: This example uses user-space network emulation, and can
**not** be used for advanced networking or larger clusters!

To test the 40-node example you *must* start `xcluster` in a [network
namespace](https://github.com/Nordix/xcluster/blob/master/doc/netns.md).
Once the netns is created, enter it and test:

```
xc nsenter 1
cd
. .bashrc
cd /your/experiment/dir/xcluster
. ./Envsettings.k8s    # (a coredns should start)
cdo test-template
./test-template.sh test --nvm=40 start_empty > /dev/null
kubectl get nodes
xc stop
```
