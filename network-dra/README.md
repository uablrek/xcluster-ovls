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

```
./network-dra.sh test start
# On a vm
kubectl create -f /etc/kubernetes/network-dra/my-net-pod.yaml
kubectl exec my-net-pod -- ifconfig -a
```

No extra network shows up. Troubleshooting in progress
