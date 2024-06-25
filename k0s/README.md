# Xcluster/ovl - k0s

The [K0s](https://k0sproject.io/) Kubernetes installed on `xcluster`

## Single node (airgap) install

As in the [Quick Start Guide](
https://docs.k0sproject.io/stable/install/#quick-start-guide), but k0s
and the airgap bundle are already loaded in `/root/www`, and no `sudo`
is required.

Howto create an airgap bundle is [described](
https://docs.k0sproject.io/stable/airgap-install/), but I couldn't
find how to use it. The only clue seem to be this:

> Note: During the worker start up k0s imports all bundles from the $K0S_DATA_DIR/images before starting kubelet

`$K0S_DATA_DIR` apparently defaults to `/var/lib/k0s`.

```
./k0s.sh test --nvm=1 start_empty
# On vm-201
ip ro delete default
tcpdump -ni eth1
# On vm-001
ln /root/www/k0s-$__k0sver-amd64 /bin/k0s
#k0s sysinfo
export K0S_DATA_DIR=/var/lib/k0s
mkdir -p $K0S_DATA_DIR/images
ln /root/www/k0s-airgap-bundle-$__k0sver-amd64 $K0S_DATA_DIR/images

k0s install controller --single
# ("k0s start" doesn't work)
service k0scontroller start
k0s kubectl get nodes
k0s kubectl get pods -A
```

To test this automatically do:
```
./k0s.sh test single
```

## Install with k0sctl


```
./k0s.sh test start
# On vm-001
export __k0sver PREFIX
k0sctl apply --disable-telemetry -c k0sctl.yaml
```

Create a base config:
```
k0sctl init --k0s --user root --key-path="/root/.ssh/id_dropbear" \
 192.168.1.1 192.168.1.2 > k0sctl-base.yaml
```

## Local registry

We must [configure containerd](https://docs.k0sproject.io/stable/runtime/)
to allow an "insecure" registry (http instead of https).

