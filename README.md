# uablrek - Xcluster overlays

Overlays for [xcluster](https://github.com/Nordix/xcluster).

```
git clone --depth 1 https://github.com/uablrek/xcluster-ovls.git \
  $GOPATH/src/github.com/uablrek/xcluster-ovls
export XCLUSTER_OVLPATH="$XCLUSTER_OVLPATH:$GOPATH/src/github.com/uablrek/xcluster-ovls"
```


## Overlay index

 * [alpine](./alpine/README.md) -  A image based on [Alpine Linux](https://www.alpinelinux.org/) with several useful additions. The image is intended as a base for other images, or test/debugging. 
 * [haproxy](./haproxy/README.md) -  Build and test [HAProxy](https://github.com/haproxy/haproxy/tree/master) 
 * [k0s](./k0s/README.md) -  The [K0s](https://k0sproject.io/) Kubernetes installed on `xcluster` 
 * [k8s-e2e](./k8s-e2e/README.md) -  Run Kubernetes e2e tests in xcluster 
 * [k8s-gateway-api](./k8s-gateway-api/README.md) -  The [K8s Gateway API](https://gateway-api.sigs.k8s.io/) on xcluster ([github](https://github.com/kubernetes-sigs/gateway-api)) 
 * [k8s-ha](./k8s-ha/README.md) -  Setup Kubernetes for High Availability (HA). This basically means to have a redundant control plane nodes behind a load balancer 
 * [k8s-ipvs-local-route](./k8s-ipvs-local-route/README.md) -  Asymmetric routing, and attempt to set a local route for ClusterIP-CIDR instead of assigning addresses to `kube-ipvs0` 
 * [k8s-load-balancing](./k8s-load-balancing/README.md) -  Test load-balancing in Kubernetes. The distribution is tested for various setups, such as proxy-mode=iptables/ipvs/nftables, and some alternatives to kube-proxy. Inspired by [Antonio's gist]( https://gist.github.com/aojea/5f82db3ba5f1efd59bb73f4b28614a6a) 
 * [k8s-metrics-server](./k8s-metrics-server/README.md) -  The [K8s metrics-server](https://github.com/kubernetes-sigs/metrics-server) in xcluster 
 * [k8s-test](./k8s-test/README.md) -  Tests of Kubernetes on xcluster. See also [ovl/tserver]( https://github.com/uablrek/xcluster-ovls/tree/main/tserver) 
 * [k8s-xcluster](./k8s-xcluster/README.md) -  Describes how [xcluster](https://github.com/Nordix/xcluster) can be used for advanced network testing with Kubernetes. 
 * [network-dra](./network-dra/README.md) -  Test https://github.com/LionelJouin/network-dra in xcluster. Use Dynamic Resource Allocation (DRA) to add networks in K8s PODs. 
 * [openrc](./openrc/README.md) -  The [OpenRC](https://github.com/OpenRC/openrc) init system in `xcluster` 
 * [runit](./runit/README.md) -  The [runit](https://smarden.org/runit/) init system on `xcluster` 
 * [tserver](./tserver/README.md) -  A test server image built on [Alpine Linux](https://www.alpinelinux.org/). The image contains various test servers and tools for trouble shooting 
 * [x-cilium](./x-cilium/README.md) -  This ovl tries to troubleshoot a bug that causes `Cilium` >=1.12 to fail on `xcluster`. The symptoms are weird, everything starts but connects via services fails *sometimes*. External access via a `loadBalancerIP` works much better that access to a `clusterIP`. 
