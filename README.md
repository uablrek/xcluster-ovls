# uablrek - Xcluster overlays

Overlays for [xcluster](https://github.com/Nordix/xcluster).


## Overlay index

 * [alpine](./alpine/README.md) -  A image based on [Alpine Linux](https://www.alpinelinux.org/) with several useful additions. The image is intended as a base for other images, or test/debugging. 
 * [haproxy](./haproxy/README.md) -  Build and test [HAProxy](https://github.com/haproxy/haproxy/tree/master) 
 * [k8s-ha](./k8s-ha/README.md) -  Setup Kubernetes for High Availability (HA). This basically means to have a redundant control plane nodes behind a load balancer 
 * [k8s-ipvs-local-route](./k8s-ipvs-local-route/README.md) -  Asymmetric routing, and attempt to set a local route for ClusterIP-CIDR instead of assigning addresses to `kube-ipvs0` 
 * [k8s-xcluster](./k8s-xcluster/README.md) -  Describes how [xcluster](https://github.com/Nordix/xcluster) can be used for advanced network testing with Kubernetes. 
 * [tserver](./tserver/README.md) -  A test server image built on [Alpine Linux](https://www.alpinelinux.org/). The image contains various test servers and tools for trouble shooting 
 * [x-cilium](./x-cilium/README.md) -  This ovl tries to troubleshoot a bug that causes `Cilium` >=1.12 to fail on `xcluster`. The symptoms are weird, everything starts but connects via services fails *sometimes*. External access via a `loadBalancerIP` works much better that access to a `clusterIP`. 
