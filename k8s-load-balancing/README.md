# Xcluster/ovl - k8s-load-balancing

Test load-balancing in Kubernetes. The distribution is tested for
various setups, such as proxy-mode=iptables/ipvs/nftables, and some
alternatives to kube-proxy. Inspired by [Antonio's gist](
https://gist.github.com/aojea/5f82db3ba5f1efd59bb73f4b28614a6a)

The tests are designed for [xcluster](https://github.com/Nordix/xcluster),
but should be possible to run on any K8s cluster with manual setup.


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
antrea-pod  iptables  ipvs      ipvs-ecmp  ipvs-lc   ipvs-lc-ecmp  ipvs-mh   nftables
   1 54        1 80    100 100     5 94     100 100    10 96          1 79      1 77
   3 59        1 81                4 95                 5 97          1 80      1 80
   1 62        1 82                5 96                21 98          1 82      1 81
   1 63        1 83                4 97                11 99          1 83      2 82
   1 64        1 84               25 98                25 100         3 84      2 84
   2 65        3 85                4 99                 2 101         1 85      5 86
   1 66        2 87                7 100                5 102         3 87      1 87
   1 67        1 89                9 101                2 103         2 88      2 88
   1 68        2 90                3 102               11 104         1 89      5 89
   5 69        1 91               15 103                2 105         3 90      2 90
   2 70        1 92               19 104                6 106         1 91      2 91
   2 71        6 94                                                   8 92      2 93
   3 72        6 95                                                   2 93      4 94
   1 73        7 96                                                   2 94      2 95
   2 74        2 97                                                   1 95      3 96
   1 75        5 98                                                   8 96      3 97
   2 76        5 99                                                   5 97      3 98
   4 77       10 100                                                  4 98      5 99
   3 78        3 101                                                  5 99      8 100
   5 80        3 102                                                  1 100     1 101
   2 81        5 103                                                  6 101     5 102
   1 83        6 104                                                  3 102     2 103
   2 84        5 105                                                  4 103     4 104
   3 85        2 106                                                  4 104     2 105
   2 86        4 107                                                  2 105     3 106
   1 87        4 109                                                  3 106     6 107
   2 88        2 110                                                  5 108     3 108
   4 90        4 112                                                  3 109     3 109
   2 91        2 114                                                  2 110     3 110
   3 92        1 115                                                  1 111     2 111
   1 93        1 116                                                  2 112     2 112
   1 94        1 118                                                  1 113     2 113
   3 95        1 130                                                  1 114     1 114
   1 96                                                               3 115     2 115
   1 98                                                               1 117     1 117
   1 102                                                              1 119     1 120
   1 131                                                              2 123     1 122
   1 133                                                              1 124     1 124
   1 137                                                              1 139     1 127
   1 140                                                                     
   3 142                                                                     
   1 144                                                                     
   1 148                                                                     
   1 149                                                                     
   2 152                                                                     
   2 155                                                                     
   2 157                                                                     
   1 158                                                                     
   2 159                                                                     
   4 162                                                                     
   2 169                                                                     
   2 171                                                                     
   1 187                                                                     
```

The first number is the number of PODs, and the second the number of
connections. So, "11 105" means that 11 PODs got 105 connections. The
[Antrea](https://antrea.io/) CNI-plugin by-passes `kube-proxy` for
connects originating from a POD.

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
./k8s-load-balancing.sh test start k8s-cni-antrea > $log
./k8s-load-balancing.sh test --tag=antrea-pod from_pod > $log
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
