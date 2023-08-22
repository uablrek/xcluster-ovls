# Xcluster/ovl - k8s-ha [WiP] Work in Progress

Setup Kubernetes for High Availability (HA). This basically means to
have a redundant control plane nodes behind a load balancer

The [K8s HA documentation](
https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/ha-topology/)
describes two options for configuring the topology:

* With stacked control plane nodes, where etcd nodes are colocated with control plane nodes
* With external etcd nodes, where etcd runs on separate nodes from the control plane

This ovl focus on external etcd nodes. To create etcd VMs we can stop
`kubelet` to start on some VMs in the 001-200 range. We also need some
free VMs for the load-balancer(s).

<img src="vm-setup.svg" width="85%" />

There are many blog posts that describe how to setup K8s-HA. They are
almosts always repeating what's already described in K8s
documentation. The [kubadam High Availability Considerations](
https://github.com/kubernetes/kubeadm/blob/main/docs/ha-considerations.md)
seems to be a good place to start.



## Cluster start

This is tricky because it differs a lot from the normal K8s start in
`xcluster`. In short, it goes like this:

  1. A init script `120k8s-ha.rc` is executed before K8s setup
  2. It moves all original K8s init scripts to `/etc/rcS.d/`
  3. The moved scripts are replaced with dummy scripts
  4. Relevant K8s init scripts are replaced with ha-adapted ones

The reason for keeping the original K8s init scripts, and not simply
over-write them, is that I hope to modify the originals rather than
maintain a totally separate K8s startup.

K8s is prevented from starting on VMs using the variable `LAST_NODE`, by
default set to 190. The K8s init scripts are modified:
```
test $i -le 200 || exit 0
# To:
test $i -le $LAST_NODE || exit 0
```
This can be added to the `xcluster` repo in the future.


The K8s start can be disabled by setting `K8S_DISABLE=yes`:
```
xcluster_K8S_DISABLE=yes ./k8s-ha.sh test start > $log
```
Etcd is still started.