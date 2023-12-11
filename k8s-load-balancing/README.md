# Xcluster/ovl - k8s-load-balancing

Test load-balancing in Kubernetes. The distribution is tested for
various setups, such as proxy-mode=iptables/ipvs/nftables, and some
alternatives to kube-proxy. Inspired by [Antonio's gist](
https://gist.github.com/aojea/5f82db3ba5f1efd59bb73f4b28614a6a)

The tests are designed for [xcluster](https://github.com/Nordix/xcluster),
but should be possible to run on any K8s cluster with manual setup.


## Base distribution test

The default setup is 100 endpoints (PODs) on 10 K8s nodes and 10,000
connects. With perfect distribution this would give 100
connects/POD. This is the case for ipvs with round-robin (rr)
scheduler, which is the default test:

```
./k8s-load-balancing.sh test external > $log
...
14:45:06 Frequencies:
    100 100
```
Here "100 100" means that 100 PODs got 100 connections.

Other results:
```
antrea-pod  cilium    iptables  ipvs      ipvs-ecmp  ipvs-lc   ipvs-lc-ecmp  ipvs-mh   nftables
   1 56        1 83      1 83    100 100     3 95       7 99      8 95          1 70      1 75
   1 57        1 84      1 84                4 96      86 100     2 96          1 71      1 78
   1 58        1 85      3 85               13 97       7 101    14 97          1 72      2 82
   1 61        2 86      1 86                4 98                20 98          1 79      1 84
   1 66        4 88      2 87               27 99                 7 99          1 83      2 86
   1 67        1 89      2 88               18 101                6 100         3 84      1 89
   2 68        2 90      1 89               16 102                1 101         1 85      6 91
   4 69        3 91      5 90                7 103               15 102         2 86      5 92
   3 70        2 92      3 91                6 104               13 103         3 87      2 93
   2 71        3 93      2 92                2 105                3 104         1 88      3 94
   1 72        2 94      5 93                                    11 105         1 89      7 95
   2 73        8 95      1 94                                                   1 90      9 96
   3 74        4 96      5 95                                                   5 92      8 97
   3 75        5 97      4 96                                                   3 93      4 98
   2 76        8 98      4 97                                                   5 94      1 99
   1 77        8 99      5 98                                                   1 95      4 101
   3 78        2 100     8 99                                                   4 96      3 102
   1 79        5 101     3 100                                                  6 97      6 103
   7 80        5 102     7 101                                                  1 98      1 104
   4 81        1 103     7 102                                                  4 99      6 105
   3 82        4 104     1 103                                                  1 100     7 106
   3 83        3 105     1 104                                                  5 101     2 107
   3 84        3 106     3 105                                                  8 102     3 108
   2 85        2 107     1 106                                                  2 103     2 109
   2 86        2 108     3 107                                                  4 104     2 111
   3 87        3 109     2 108                                                  4 106     3 112
   3 88        4 110     1 109                                                  6 107     1 113
   1 89        1 111     5 110                                                  7 109     1 114
   4 92        2 112     3 113                                                  2 110     2 118
   1 94        2 113     2 114                                                  3 111     1 119
   2 95        3 114     1 115                                                  1 112     1 120
   1 100       1 115     1 116                                                  3 113     1 123
   1 114       1 117     1 117                                                  3 114     1 125
   2 138       1 127     1 118                                                  1 117  
   1 143                 1 119                                                  1 119  
   1 145                 2 120                                                  1 122  
   2 146                 1 121                                                  1 123  
   1 147                                                                        1 125  
   3 149                                                                               
   1 150                                                                               
   2 151                                                                               
   1 153                                                                               
   1 154                                                                               
   2 156                                                                               
   1 159                                                                               
   1 161                                                                               
   2 165                                                                               
   1 170                                                                               
   1 171                                                                               
   1 172                                                                               
   1 173                                                                               
   1 176                                                                               
   1 178
```

The first number is the number of PODs, and the second the number of
connections. So, "11 105" means that 11 PODs got 105 connections. The
[Antrea](https://antrea.io/) CNI-plugin by-passes `kube-proxy` for
connects originating from a POD.

Generate the table above with:
```
./k8s-load-balancing.sh table ./saves/mconnect-*
# Re-run:
rm /tmp/mconnect-*
./k8s-load-balancing.sh test external > $log
./k8s-load-balancing.sh test --ecmp --tag=ipvs-ecmp external > $log
./k8s-load-balancing.sh test --mode=iptables external > $log
./k8s-load-balancing.sh test --mode=nftables external > $log
xcluster_IPVS_SCHEDULER=mh ./k8s-load-balancing.sh test --tag=ipvs-mh external > $log
xcluster_IPVS_SCHEDULER=lc ./k8s-load-balancing.sh test --tag=ipvs-lc external > $log
xcluster_IPVS_SCHEDULER=lc ./k8s-load-balancing.sh test --tag=ipvs-lc-ecmp --ecmp external > $log
#xcluster_IPVS_SCHEDULER=sh ./k8s-load-balancing.sh test --tag=ipvs-sh external > $log
./k8s-load-balancing.sh test start k8s-cni-antrea > $log
./k8s-load-balancing.sh test --tag=antrea-pod from_pod > $log
./k8s-load-balancing.sh test start_cilium > $log
./k8s-load-balancing.sh test --no-start --no-stop --tag=cilium external > $log
./k8s-load-balancing.sh table /tmp/mconnect-*
```

#### Cilium bug

`Cilium` often lose connections, made worse by ecmp. Probably
related to [issue #20297](https://github.com/cilium/cilium/issues/20297).
Eventually it works.

## Manual tests

Start with the desired combination, then:
```
# On host
./k8s-load-balancing.sh test conntrack_clear
# On vm-201
conntrack -F; mconnect -address 10.0.0.1:5001 -nconn 10000 -srccidr 20.0.0.0/16 -output json | jq
conntrack -F; mconnect -address 10.0.0.1:5001 -nconn 10000 -output json -timeout 2m -srccidr 20.0.0.0/16 | jq
conntrack -F; mconnect -address [fd00::10.0.0.1]:5001 -nconn 10000 -srccidr fd00::20.0.0.0/112 -output json | jq
# IPv4 RST
tcpdump -ni eth1 'tcp[tcpflags] & (tcp-rst) !=0'
# IPv6 RST
tcpdump -ni eth1 'ip6[13+40]&0x04!=0'
# Reboot vm-201
reboot
k8s-load-balancing_test tcase_conntrack_size 420000
k8s-load-balancing_test tcase_add_address_range
k8s-load-balancing_test tcase_vip_routes 192.168.1.2
```


## Run in any cluster

First bring up your test cluster, for instance KinD, with the
configuration you want to test, then:

```
kubectl create -f default/etc/kubernetes/k8s-load-balancing/svc-tserver.yaml
kubectl create -f default/etc/kubernetes/k8s-load-balancing/tserver.yaml
kubectl wait --for=condition=Ready pod --selector=app=tserver --timeout=5m # (is there a better way?)
./k8s-load-balancing.sh test from_pod > $log
```

This runs `mconnect` from a tserver POD, so nothing else is needed
(but "hairpin" connect must work).

You can also connect to a `nodePort`, but be aware:

**WARNING:** To do very many connects puts a lot of stress on the traffic
generator. Resources like ephemeral ports and conntrack entries may be
exhausted.

Install [mconnect](https://github.com/Nordix/mconnect) in your $PATH, then:
```
# Get a node address. Here a KinD cluster named "nftables" is assumed
docker inspect nftables-control-plane | jq -r .[0].NetworkSettings.Networks.kind.IPAddress
172.18.0.3
./k8s-load-balancing.sh test nodeport 172.18.0.3 > $log
```
