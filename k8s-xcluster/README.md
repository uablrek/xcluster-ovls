# Xcluster/ovl - k8s-xcluster

Describes how [xcluster](https://github.com/Nordix/xcluster) can be
used for advanced network testing with Kubernetes.

**Xcluster is not a Kubernetes test tool!**

It is primarily a **networking** test tool that can be used with
Kubernetes. For K8s development in general, there are far more
suitable environments like [KinD](https://kind.sigs.k8s.io/).

Xcluster makes it possible to test network features in virtual
environment that other environments doesn't support, like:

* Easy switch between different CNI-plugins or kube-proxy modes
* [K8s HA setup](https://github.com/uablrek/xcluster-ovls/tree/main/k8s-ha)
* SR-IOV without a supporting HW NIC (requires qemu 8)
* [Different network topologies](
  https://github.com/Nordix/xcluster/blob/master/ovl/network-topology/README.md)
* Test any kernel setup, e.g. kernel versions, config or eBPF

### It's fast and lightweight

A 40-node K8s cluster started in less than 10s:

<img src="xcluster40.svg" width="50%" />

A reason for the fast start is that no container images are
loaded. All files are pre-loaded on the image, and K8s is started from
scripts. (the PC is an Intel i9 with 64G RAM)

### You always restart xcluster

An `xcluster` is never left running and re-used for several tests. A
test usually look like:

1. Start xcluster with appropriate [overlays](#overlays)
2. Execute tests
3. Terminate xcluster

Some advantages of this approach are:

* There is never any lingering stale state that causes problems
* It's simple to alter the test setup, e.g. with different kernels,
  different CNI-plugins, different K8s versions, etc
* The overlay with the test is preserved (and hopefully documented),
  and can be re-used years later. IMO this "preservability" property
  is one of the most important

An example that uses the `xcluster` [test framework](
https://github.com/Nordix/xcluster/tree/master/ovl/test):

<img src="simple-test.svg" width="50%" />

A simple connectivity test is performed with:

* Proxy-mode=nftables and cni-plugin calico
* Default proxy-mode (ipvs) and cni-plugin flannel, but with kernel 5.10.215

You might notice that the start of this 4-node cluster took longer
time than the 40-node cluster in the example above? This is because
the cni-plugins must be loaded and started.


### Installation

The images can't be maintained on `Nordix` at the moment, so download
from:

* [xcluster.tar.xz](
  https://drive.google.com/file/d/1-2OTYGUxkAobs0Ouup3b7h13apu_CONs/view?usp=drive_link)
* [hd-k8s.img.xz](
  https://drive.google.com/file/d/1tGta6gr-bLtyVmfBSpaw41lESummvHDG/view?usp=drive_link)

Check the [dependencies](
https://github.com/Nordix/xcluster#execution-environment-and-dependencies),
then:

```
cd /your/experiment/dir
tar xf $HOME/Downloads/xcluster.tar.xz
cd xcluster
. ./Envsettings
xc mkcdrom xnet iptools
xterm        # Optional. Just test that "xterm" works
xc start     # 6 xterm consoles (xterm) should pop up
xc stop
```

Please read [the troubleshooting document](
https://github.com/Nordix/xcluster/blob/master/doc/troubleshooting.md)
if needed.

Add k8s (continuation from above):
```
. ./Envsettings.k8s
# The printouts say that you have no k8s image. Load it:
xz $HOME/Downloads/hd-k8s.img.xz -cd -T0 > $__image
xc mkcdrom   # clear ovl's
xc start     # 6 xterm consoles should pop up, but now with K8s
# $KUBECONFIG is set for you. You can install "kubectl" yourself,
# or use:
./workspace/bin/kubectl get nodes
xc stop
```

**WARNING**: This example uses user-space network emulation, and can
**not** be used for advanced networking or larger clusters!

To test the 40-node example you *must* start `xcluster` in a [network
namespace](https://github.com/Nordix/xcluster/blob/master/doc/netns.md).
Once the netns is created, enter it and test:

```
#xc nsadd_docker 1
xc nsenter 1
cd
. .bashrc
cd /your/experiment/dir/xcluster
. ./Envsettings.k8s    # (a coredns should start)
cdo template-k8s
export __log=/tmp/$USER/xcluster.log
./template-k8s.sh test --nvm=40 start_empty
vm 22                # Terminal on vm-022
kubectl get nodes
xc stop
```


### Overlays

Overlays in `xcluster` are archives that are unpacked in order to the
root file system at startup. However, usually "overlay" refer to a
directory with a script that creates the archive:

```
# xcadmin mkovl --template=template --ovldir=. my-ovl
# find my-ovl -type f
my-ovl/my-ovl.sh
my-ovl/README.md
my-ovl/tar
my-ovl/default/bin/my-ovl_test
```

An overlay directory (ovl) *must* contain a `tar` script that writes a
tar image. In all ovl's you can check what will be installed with:

```
./tar - | tar t
```

An ovl should also contain a script with the same name as the ovl, and
a `README.md`. This is optional, but a uniform structure is
desirable. The script usually has at least a "test start" function:

```
log=/tmp/xcluster.log
cd my-ovl
./my-ovl.sh test start lspci > $log
vm 1
# In the terminal window
lspci
```

Any number of additional ovl's can be added after the test command. In
the example `ovl/lspci` is included.

The `$XCLUSTER_OVLPATH` contains directories where `xcluster` search
for ovls. There are several functions that helps with ovl handling:

```
lso                 # List ovls
cdo <ovl>           # Cd to an ovl with command completion
xc ovld <ovl>       # Print the path to an ovl
xcadmin mkovl ...   # Create a new ovl
```


## Kubernetes environment

To make network tests with K8s you need:

1. To start xcluster in it's own [network namespace](
   https://github.com/Nordix/xcluster/blob/master/doc/netns.md) (mandatory)
2. A [private registry](
   https://github.com/Nordix/xcluster/blob/master/ovl/private-reg/README.md)
   (optional, but *highly* recommended, and assumed from now on)

Run the basic test:
```
export __log=/tmp/$USER/xcluster.log   # (assumed to be set from now on)
export XOVLS=private-reg
images lreg_preload kubernetes mconnect
cdo template-k8s
./template-k8s.sh test default
```

### Use another CNI-plugin

```
images lreg_preload k8s-cni-calico
cdo template-k8s
./template-k8s.sh test --cni=calico
```

The local registry must be pre-loaded with the necessary images, then
add the cni ovl to the test command. Available CNI-plugins are:

* [k8s-cni-antrea](https://github.com/Nordix/xcluster/tree/master/ovl/k8s-cni-antrea) (requires ovl/ovs)
* [k8s-cni-calico](https://github.com/Nordix/xcluster/tree/master/ovl/k8s-cni-calico)
* [k8s-cni-flannel](https://github.com/Nordix/xcluster/tree/master/ovl/k8s-cni-flannel)
* [k8s-cni-xcluster](https://github.com/Nordix/xcluster/tree/master/ovl/k8s-cni-xcluster)
* [k8s-cni-cilium](https://github.com/Nordix/xcluster/tree/master/ovl/k8s-cni-cilium) (will by-pass kube-proxy)


### ovl/env

The `env` ovl is included by default by the test scripts. It makes all
environment variables beginning with "xcluster_" appear on all VM (but
without the "xcluster_" prefix).

```
cdo test-template
xcluster_HELLO=World ./test-template.sh test start_empty > $log
# On any VM
# echo $HELLO
World
```

The `/etc/profile` file must be sourced in scripts.

There are several variables that are used in tests, for example:

* xcluster_TZ - Set the time-zone ([ovl/timezone](https://github.com/Nordix/xcluster/tree/master/ovl/timezone))
* xcluster_DOMAIN - The domain is "xcluster" by default, but many programs (wrongly) assumes "cluster.local"
* xcluster_FEATURE_GATES - Comma separated, no spaces
* xcluster_BASE_FAMILY - IPv4 (default), or IPv6
* xcluster_PROXY_MODE - "ipvs" (default), "iptables", or "disabled"

Example:
```
export xcluster_TZ=EST+5EDT,M3.2.0/2,M11.1.0/2
xcluster_BASE_FAMILY=IPv6 xcluster_PROXY_MODE=disabled xcluster_DOMAIN=cluster.local \
 ./test-template.sh test start_empty k8s-cni-cilium > $log
# On a cluster VM
# date
Thu Nov 23 15:19:26 EST 2023
# nslookup kubernetes.default.svc.cluster.local
Server:         192.168.0.2
Address:        192.168.0.2:53


Name:   kubernetes.default.svc.cluster.local
Address: fd00:4000::1
```
