# Xcluster/ovl - k8s-gateway-api

The [K8s Gateway API](https://gateway-api.sigs.k8s.io/) on xcluster
([github](https://github.com/kubernetes-sigs/gateway-api))


## Install gateway-api

Normal start:
```
./k8s-gateway-api.sh get_manifests
images lreg_preload default k8s-pv
./k8s-gateway-api.sh test start > $log
# On a node
kubectl get crds
kubectl describe crd gatewayclasses.gateway.networking.k8s.io
```


## nginx-gateway-fabric

The [nginx-gateway-fabric](https://github.com/nginxinc/nginx-gateway-fabric)
seem to be closest to a reference implementation. Install with [manifests](
https://docs.nginx.com/nginx-gateway-fabric/installation/installing-ngf/manifests/):

```
git clone --depth 1 https://github.com/nginxinc/nginx-gateway-fabric.git --branch v1.0.0 \
  $GOPATH/src/github.com/nginxinc/nginx-gateway-fabric
./k8s-gateway-api.sh get_nginx_manifests
images lreg_preload nginx-gateway-fabric
./k8s-gateway-api.sh test start_nginx > $log
```

### Problem

Nginx doesn't start:
```
pod=$(kubectl get pods -n nginx-gateway -o name | head -1)
kubectl logs -n nginx-gateway $pod -c nginx
2023/12/02 08:50:04 [emerg] 23#23: io_setup() failed (38: Function not implemented)
```

A description found [here](
https://forum.turris.cz/t/nginx-errors-in-log-due-to-missing-kernel-syscall/14798), but `setitimer` is in the kernel, as is `epoll`. Why does this happen??



## Links

* https://github.com/envoyproxy/gateway
* https://gateway-api.sigs.k8s.io/concepts/gamma/
* https://isovalent.com/blog/post/tutorial-getting-started-with-the-cilium-gateway-api/
* http://nginx.org/en/docs/ngx_core_module.html#use