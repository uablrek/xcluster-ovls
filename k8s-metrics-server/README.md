# Xcluster/ovl - k8s-metrics-server

The [K8s metrics-server](https://github.com/kubernetes-sigs/metrics-server)
in xcluster

This ovl is intended to be included when the K8s `metrics-server` is
needed. It is needed to make "kubectl top" work, and for [autoscale](
https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/).


## Test

```
# Just test that metrics-server starts ok
./k8s-metrics-server.sh test default
# Manual test
./k8s-metrics-server.sh test start
# On a vm (after some time)
vm-002 ~ # kubectl top nodes
NAME     CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%   
vm-001   210m         10%    635Mi           64%
vm-002   68m          3%     175Mi           24%
vm-003   72m          3%     181Mi           24%
vm-004   66m          3%     176Mi           24%
vm-002 ~ # kubectl top pods
NAME                       CPU(cores)   MEMORY(bytes)   
tserver-569b74646b-hzdgr   0m           3Mi
tserver-569b74646b-mtcsb   0m           3Mi
tserver-569b74646b-qjqq7   0m           3Mi
tserver-569b74646b-wnfb6   0m           3Mi
```


## Update

```
curl -L https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml > components.yaml
meld default/etc/kubernetes/load/components.yaml components.yaml
# update...
images lreg_preload default
```

The option `--kubelet-insecure-tls` must be added.
