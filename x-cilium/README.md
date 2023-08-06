# Xcluster/ovl - x-cilium

This ovl tries to troubleshoot a bug that causes `Cilium` >=1.12 to
fail on `xcluster`. The symptoms are weird, everything starts but
connects via services fails *sometimes*. External access via a
`loadBalancerIP` works much better that access to a `clusterIP`.

On Cilium v1.12
```
# Works from vm-201 (router)
> mconnect -address 10.0.0.0:5001 -nconn 100
Failed connects; 0
Failed reads; 0
alpine-f6c8bd7db-vrddx 22
alpine-f6c8bd7db-f26bt 22
alpine-f6c8bd7db-fb66j 29
alpine-f6c8bd7db-29zj6 27
# But on vm-002
> mconnect -address 10.0.0.0:5001 -nconn 100
Read err: read tcp 192.168.1.2:35112->10.0.0.0:5001: read: connection reset by peer
...
Failed connects; 54
Failed reads; 11
alpine-f6c8bd7db-29zj6 12
alpine-f6c8bd7db-fb66j 7
alpine-f6c8bd7db-vrddx 9
alpine-f6c8bd7db-f26bt 7
> mconnect -address alpine.default.svc.xcluster:5001 -nconn 100
Failed connects; 100
Failed reads; 0
```

Bad commits are traced with `git bisect`, example:

```
cdg cilium
git checkout main
git bisect start 5c53222034399a811 fef5928d0bbadd5a  # bad good
rm -f /tmp/$USER/xcluster/cilium-test.log
git bisect run $($XCLUSTER ovld x-cilium)/x-cilium.sh build_and_test
```

Unfortunately, there is not just *one* bad commit. It stops working on
some commit, and is corrected later, and then fails again on an even
later commit. This makes it considerably harder.



## Finding commits on the main branch

We want to run `git bisect` on the `main` branch. There are release
branches for `v1.11` and `v1.12`, and we want the commits on the
`main` branch where the release branches forks.

```
cdg cilium
git checkout v1.11
git merge-base v1.11 main
f313f7dfc0a589c09d7e6d811cef11163b970568
git checkout v1.12
git merge-base v1.12 main
5c53222034399a811f7eb7a414c458ad449334b0
```

(there may be better ways than to actually checkout the release
branches, but this works)


## The problem and the solution

As mentioned, there are several bad commits on the `main` branch
between v1.11 and v1.12, and we want the latest. This is the culprit:

```
commit 28bffa6d4b11936f9c2dc94a68dec0ecd4d3f745
Author: André Martins <andre@cilium.io>
Date:   Thu Dec 17 20:11:48 2020 +0100

    install/kubernetes: remove privileged from Cilium DaemonSet
    
    Cilium container does not require to run as privileged so we can
    effectively remove "privileged: true" and set a minimal set of
    capabilities required for Cilium to run.
    
    Signed-off-by: André Martins <andre@cilium.io>
```

Checking the commit, it looks like seLinux, apparmor, and possible
other things are assumed that are not in `xcluster`. The simple
solution is to specify:

```
--set securityContext.privileged=true
```

to `helm` to run in privileged mode. With this small update it is
possible to run Cilium v1.14.0 (latest at the time of writing) on `xcluster`.



## Devenv setup

Read [the docs](
https://docs.cilium.io/en/stable/contributing/development/dev_setup/).

```
#git clone https://github.com/cilium/cilium.git $GOPATH/src/github.com/cilium/cilium
cdg cilium
make dev-doctor
# Update, and this might be needed afterwards:
#go mod tidy
#go mod vendor
make precheck
#different go-versions are required for different versions
```

## Build

```
cdg cilium
git reset --hard HEAD
git clean -dxf
git checkout v1.11
make precheck build
make docker-cilium-image docker-operator-generic-image
```
