# Xcluster/ovl - network-dra

Test https://github.com/LionelJouin/network-dra in xcluster. Use
Dynamic Resource Allocation (DRA) to add networks in K8s PODs.

## Prep

A local private registry is assumed

```
eval $(./network-dra.sh env | grep NETWORK_DRA_DIR)
git clone https://github.com/LionelJouin/network-dra.git $NETWORK_DRA_DIR
./network-dra.sh images
./network-dra.sh build
```

## Basic test

Manual:
```
./network-dra.sh test start
# On a vm
kubectl create -f /etc/kubernetes/network-dra/demo-a.yaml
kubectl exec demo-a -- ifconfig -a
```

Automatic:
```
./network-dra.sh test
```


## KinD

```
./network-dra.sh kind
kubectl create -f https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/e2e/templates/cni-install.yml.j2
kubectl create -f default/etc/kubernetes/network-dra/multus-daemonset-thick.yml
kubectl create -f default/etc/kubernetes/network-dra/network-dra.yaml

eval $(./network-dra.sh env | grep NETWORK_DRA_DIR)
kubectl create -f $NETWORK_DRA_DIR/examples/demo-a.yaml
kubectl exec demo-a -- ifconfig -a
./network-dra.sh kind --stop
```
