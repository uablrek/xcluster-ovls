# Xcluster/ovl - k8s-e2e

Run Kubernetes e2e tests in xcluster


K8s e2e uses `ginkgo`. Install it and build the test program:
```
go install -mod=mod github.com/onsi/ginkgo/v2/ginkgo
cd $GOPATH/src/k8s.io/kubernetes
make WHAT=test/e2e/e2e.test
```

Since `xcluster` normally uses a local registry it must be loaded with
the images the e2e tests require.

```
./k8s-e2e.sh e2e_cache
```

The tests are selected with the $FOCUS and $SKIP environment
variables. By default conformance tests for services are executed.

```
./k8s-e2e.sh test --wait start_empty
./k8s-e2e.sh e2e_list    # Lists the test-cases without executing them
./k8s-e2e.sh e2e_run
# Some FOCUS/SKIP examples:
export FOCUS='\[sig-network\].*ervice.*'  # select all service tests
export SKIP='Disruptive|Serial|ESIPP|DNS|GCE|finalizer|ServiceCIDRs'
export FOCUS='\[sig-node\].*[Cc]onformance.*'
export SKIP='Disruptive|Serial|with.secret|Slow'
```
