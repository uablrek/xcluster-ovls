# Xcluster/ovl - k8s-test

Tests of Kubernetes on xcluster. See also [ovl/tserver](
https://github.com/uablrek/xcluster-ovls/tree/main/tserver)

This was my main test ovl for some years and has accumulated many
test-cases on a need-to-test basis. This role has now been taken over by
[ovl/tserver](https://github.com/uablrek/xcluster-ovls/tree/main/tserver),
mainly because of the use of ovls on Nordix, e.g. [ovl/mserver](
https://github.com/Nordix/xcluster/tree/master/ovl/mserver), which I can't
modify easily any more.

It is provided as-is with minimal maintenance.



## Usage

```
cdo k8s-test
./k8s-test.sh     # help printout
# basic tests with Calico
images lreg_preload . k8s-cni-calico
xcluster_BASE_FAMILY=IPv6 xcluster_PROXY_MODE=iptables \
./k8s-test.sh test basic k8s-cni-calico > $log
# Repeated tests with the nftables proxier (requires K8s >= v1.29)
export xcluster_BASE_FAMILY=IPv6
export xcluster_PROXY_MODE=nftables
export xcluster_FEATURE_GATES=NFTablesProxyMode=true \
while ./k8s-test.sh test basic k8s-cni-calico > $log; do date; done
```


## Upgrade test

Will upgrade from the version running on start to `$__newver`, which
is `master` by default. The "upgrade" is simply to replace all K8s
binaries and "killall" K8s servers.

The new version must be either built on
`$GOPATH/src/k8s.io/kubernetes` (for "master") or be unpacked at
`$KUBERNETESD` which defaults to "$HOME/tmp/kubernetes".

```
ls -F $HOME/tmp/kubernetes
kubernetes-v1.29.0-rc.0/
./k8s-test.sh test --newver=v1.29.0-rc.0 upgrade_with_traffic > $log
```
No traffic should be lost during a K8s upgrade.



## SCTP

```
export xcluster_PROXY_MODE=iptables
__nrouters=1 k8s test "k8s-test start_sctp"
# On vm-201
ncat --sctp 1000::77 7002     # hostname
ncat --sctp 1000::77 7003     # sh
ncat --udp 1000::78 7005      # hostname
ncat --udp 1000::78 7006      # sh
ncat 1000::79 7008            # hostname
ncat 1000::79 7009            # sh
npsctp=$(kubectl get svc mserver-sctp -o json | jq -r '.spec.ports[]|select(.name == "sctp-sh")|.nodePort')
ncat --sctp 192.168.1.2 $npsctp
npudp=$(kubectl get svc mserver-sctp-udp -o json | jq -r '.spec.ports[]|select(.name == "udp-sh")|.nodePort')
ncat --udp 192.168.1.2 $npudp
# On a vm
kubectl label nodes vm-002 app-
kubectl label nodes --all app=mserver-sctp
conntrack -L -p sctp
conntrack -L -p udp
conntrack -D -p sctp -s 192.168.1.201
kubectl delete svc mserver-sctp
kubectl delete svc mserver-sctp-udp
kubectl delete svc mserver-sctp-tcp
```

## Manual UDP tests

For test of
[kube-proxy IPVS break UDP NodePort Services by clearing active conntrack entries](https://github.com/kubernetes/kubernetes/issues/113802).

```
xcluster_PROXY_MODE=iptables \
./k8s-test.sh test start_empty kube-proxy > $log
kubectl apply -f /etc/kubernetes/k8s-test/svc-udp/svc-udp.yaml
# In the POD
pod=$(kubectl get pods -l app=udp-app -o name)
kubectl exec -it $pod -- sh
nc -u -l -p 5005
# On vm-201
nodeport=$(kubectl get svc udp-svc -o json | jq '.spec.ports[]|select(.name == "nc-udp").nodePort')
nc -u 192.168.1.2 $nodeport
# On vm-002
echo 300 > /proc/sys/net/netfilter/nf_conntrack_udp_timeout_stream
echo 120 > /proc/sys/net/netfilter/nf_conntrack_udp_timeout
watch conntrack -L -p udp
watch ipvsadm -Ln
tail -f /var/log/kube-proxy.log
```
