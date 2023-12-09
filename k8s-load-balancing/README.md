# Xcluster/ovl - k8s-load-balancing

Test load-balancing in Kubernetes. The distribution is tested for
various setups, such as proxy-mode=iptables/ipvs/nftables, and some
alternatived to kube-proxy, such as Cilium. Inspired by [Antonio's gist](
https://gist.github.com/aojea/5f82db3ba5f1efd59bb73f4b28614a6a)

The tests are designed for [xcluster](https://github.com/Nordix/xcluster),
but many should be possible to run on any K8s cluster with manual setup.


## Base distribution test

The default setup is 100 endpoints (PODs) and 10,000 connects. With
perfect distribution this would give 100 connects/POD. This is the
case for ipvs with round-robin (rr) scheduler, which is the default test:

```
./k8s-load-balancing.sh test external > $log
...
14:45:06 Frequencies:
    100 100
```
Here "100 100" means that 100 PODs got 100 connections.

Other results:
```
iptables  ipvs      ipvs-ecmp  ipvs-lc   ipvs-lc-ecmp  ipvs-mh   nftables
   1 75    100 100     1 94      12 99     11 95          2 75      1 67
   1 78               10 95      78 100     4 96          1 77      1 81
   1 81                3 96       8 101     4 97          1 78      1 82
   3 82                3 97       2 102     9 98          1 80      5 87
   1 85                3 98                21 99          2 81      3 88
   2 87                6 99                21 100         2 82      9 89
   4 89               21 100                3 102         3 83      2 91
   2 90               32 101                3 103         1 84      4 92
   4 91                7 102               13 104         2 85      2 93
   1 92               13 103               11 105         1 88      4 94
   8 93                1 104                              2 89      4 95
   3 94                                                   2 90      2 96
   2 95                                                   4 92      5 97
   6 96                                                   2 93      6 98
   2 97                                                   1 94      2 100
   2 98                                                   4 95      2 101
   5 99                                                   7 96      5 102
   3 100                                                  6 97      3 103
   4 101                                                  2 98      2 104
   4 102                                                  2 99      4 105
   3 103                                                  4 100     4 106
   5 104                                                  2 101     7 107
   5 105                                                  7 102     2 108
   3 106                                                  5 103     4 109
   3 107                                                  3 104     1 110
   3 108                                                  2 105     3 111
   2 109                                                  2 106     4 112
   1 110                                                  2 108     2 113
   2 111                                                  2 109     1 114
   3 112                                                  2 110     3 116
   3 113                                                  4 111     1 124
   2 114                                                  3 112     1 136
   1 115                                                  2 113  
   1 116                                                  1 114  
   1 117                                                  3 115  
   1 118                                                  1 116  
   1 120                                                  2 117  
   1 124                                                  1 122  
                                                          2 124  
                                                          1 125  
                                                          1 135  
```

The first number is the number of PODs, and the second the number of
connections. So, "11 105" means that 11 PODs got 105 connections.

Generate the table above with:
```
rm /tmp/mconnect-*
./k8s-load-balancing.sh test external > $log
./k8s-load-balancing.sh test --ecmp --tag=ipvs-ecmp external > $log
./k8s-load-balancing.sh test --mode=iptables external > $log
./k8s-load-balancing.sh test --mode=nftables external > $log
xcluster_IPVS_SCHEDULER=mh ./k8s-load-balancing.sh test --tag=ipvs-mh external > $log
xcluster_IPVS_SCHEDULER=lc ./k8s-load-balancing.sh test --tag=ipvs-lc external > $log
xcluster_IPVS_SCHEDULER=lc ./k8s-load-balancing.sh test --tag=ipvs-lc-ecmp --ecmp external > $log
#xcluster_IPVS_SCHEDULER=sh ./k8s-load-balancing.sh test --tag=ipvs-sh external > $log
./k8s-load-balancing.sh table /tmp/mconnect-*
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

```
# Get a node address. Here a KinD cluster named "nftables" is assumed
docker inspect nftables-control-plane | jq -r .[0].NetworkSettings.Networks.kind.IPAddress
172.18.0.3
./k8s-load-balancing.sh test nodeport 172.18.0.3 > $log
```
