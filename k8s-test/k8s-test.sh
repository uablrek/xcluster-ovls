#! /bin/sh
##
## k8s-test.sh --
##
##   Help script for the xcluster ovl/k8s-test.
##
## Commands;
##

prg=$(basename $0)
dir=$(dirname $0); dir=$(readlink -f $dir)
me=$dir/$prg
tmp=/tmp/${prg}_$$
test -n "$FIRST_WORKER" || FIRST_WORKER=1

die() {
    echo "ERROR: $*" >&2
    rm -rf $tmp
    exit 1
}
help() {
    grep '^##' $0 | cut -c3-
    rm -rf $tmp
    exit 0
}
test -n "$1" || help
echo "$1" | grep -qi "^help\|-h" && help

log() {
	echo "$prg: $*" >&2
}
dbg() {
	test -n "$__verbose" && echo "$prg: $*" >&2
}

##   env
##     Print environment.
cmd_env() {
	test -n "$__newver" || __newver=master
	test -n "$__registry" || __registry=docker.io/uablrek
	test -n "$KUBERNETESD" || KUBERNETESD=$HOME/tmp/kubernetes
	if test "$cmd" = "env"; then
		local opt="newver|registry"
		set | grep -E "^(__($opt)|KUBERNETESD)="
		return 0
	fi

	images=$($XCLUSTER ovld images)/images.sh
	test -n "$xcluster_DOMAIN" || xcluster_DOMAIN=xcluster
	test -n "$XCLUSTER" || die 'Not set [$XCLUSTER]'
	test -x "$XCLUSTER" || die "Not executable [$XCLUSTER]"
	eval $($XCLUSTER env)
	if echo "$xcluster_PROXY_MODE" | grep -q nftables; then
		tlog "Set feature-gate [NFTablesProxyMode=true]"
		export xcluster_FEATURE_GATES=NFTablesProxyMode=true
	fi
}
##   pack_k8s --dest=<dir> [--newver=master]
##     Pack the K8s binaries into an archive (called from ./tar on upgrade)
cmd_pack_k8s() {
	cmd_env
	test -n "$__dest" || die "No --dest"
	test -n "$__newver" || __newver=master
	local k8sd=$GOPATH/src/k8s.io/kubernetes/_output/bin
	test "$__newver" = "master" || \
		k8sd=$KUBERNETESD/kubernetes-$__newver/server/bin
	local f
	mkdir -p $tmp/bin
	for f in kube-apiserver kube-controller-manager kubectl \
		kubelet kube-proxy kube-scheduler; do
		test -x $k8sd/$f || die "Not executable [$k8sd/$f]"
		cp $k8sd/$f $tmp/bin
	done
	mkdir -p $__dest
	tar -C $tmp -cf $__dest/newk8s.tar bin
}
##   inject
##     Inject ovl/k8s-test to VMs
cmd_inject() {
	local n
	test -n "$__nvm" || __nvm=4
	for n in $(seq 1 $__nvm) 201 202; do
		echo "Inject test k8s-test to 192.168.0.$n"
		$XCLUSTER inject --addr=root@192.168.0.$n k8s-test || die
	done
}
##   build_alpine_test
##     Build the "alpine-test" image and upload to local-reg
cmd_build_alpine_test() {
	cmd_env
	local tag=$__registry/alpine-test:latest
	local dockerfile=$dir/alpine-test/Dockerfile
	mkdir -p $tmp
	docker build -t $tag -f $dockerfile $tmp || die "docker build $base"
	$images lreg_upload $tag
}

##
##   test [--xterm] [--no-stop] [test x-ovls...] > logfile
##     Exec tests
cmd_test() {
	if test "$__list" = "yes"; then
        grep '^test_' $me | cut -d'(' -f1 | sed -e 's,test_,,'
        return 0
    fi

	cmd_env
	cd $dir
    start=starts
    test "$__xterm" = "yes" && start=start
    rm -f $XCLUSTER_TMP/cdrom.iso

    if test -n "$1"; then
		local t=$1
		shift
		test_$t $@
    else
		test_basic
    fi      

    now=$(date +%s)
    tlog "Xcluster test ended. Total time $((now-begin)) sec"

}

##   test start_empty
##     Start cluster without servers
test_start_empty() {
	if test -n "$TOPOLOGY"; then
		tlog "WARNING: network-topology [$TOPOLOGY]"
		export xcluster_TOPOLOGY=$TOPOLOGY
		. $($XCLUSTER ovld network-topology)/$TOPOLOGY/Envsettings
	fi
	xcluster_start network-topology . $@
	otc 1 check_namespaces
	otc 1 check_nodes
	otcr vip_routes
}
##   test start
##     Start cluster and servers
test_start() {
	test_start_empty $@
	if test "$__multus" = "yes"; then
		tcase "Installing Multus"
		kubectl apply -f $($XCLUSTER ovld multus)/multus-install.yaml
	fi
	otc 1 start_servers
}
##   test start_sctp
##     Start cluster and SCTP server
test_start_sctp() {
	test_start_empty $@
	otcr "set_route 10.0.0.0/24 192.168.1.2"
	otcr "set_route 1000::/120 1000::1:192.168.1.2"
	otc 1 start_sctp
}
##   test start_hugep
##     Start cluster with huge-pages
test_start_hugep() {
	local n
	for n in $(seq $FIRST_WORKER $__nvm); do
		eval export __append$n="hugepages=128"
	done
	test_start_empty $@
}
##   test start_mserver2
##     Setup a mserver deployment and a svc, and NOTHING ELSE.
test_start_mserver2() {
	test -n "$__nrouters" || export __nrouters=1
	export xcluster_PREFIX=$PREFIX
	test_start_empty $@
	otc 1 mserver2
}
##   test basic (default)
##     Basic K8s tests
test_basic() {
	test_start $@

	echo "$xcluster_IPV6_PREFIX" | grep -q : && tlog "Main-family IPv6"
	otc 1 podip
	otc 1 dual_services
	otc 1 headless_services

	otc 1 "scale 8"
	otc 1 "scale 4"

	otc 2 "mconnect mserver.default.svc.$xcluster_DOMAIN"
	otc 2 "mconnect mserver app=mserver"
	otc 2 "mconnect mserver app=mserver-hostnet"
	otc 2 "mconnect mserver-hostnet.default.svc.$xcluster_DOMAIN"
	otc 2 "mconnect mserver-hostnet app=mserver"
	otc 2 "mconnect mserver-hostnet app=mserver-hostnet"

	otc 201 external_traffic
	otc 201 external_http

	xcluster_stop
}
##   test affinity
##     Test Service session affinity
test_affinity() {
	export __nrouters=1
	test -n "$xcluster_PROXY_MODE" || export xcluster_PROXY_MODE=ipvs
	echo $@ | grep -q cilium && export xcluster_PROXY_MODE=disabled
	tlog "=== k8s-test: Affinity test"
	test_start $@
	otc 201 add_srccidr
	otc 201 "affinity 10.0.0.60"
	otc 201 "affinity 1000::60"
	xcluster_stop
}
##   test [--newver=] upgrade
##     Test K8s upgrade
test_upgrade() {
	test -n "$__newver" || __newver=master
	export __newver
	tlog "=== k8s-test: Upgrade to $__newver"
	test_start_empty
	otc 1 upgrade_master
	sleep 2
	otc 1 "check_namespaces 120"
	local n	
	for n in $(seq 2 $__nvm); do
		otc $n upgrade_worker
	done
	otc 1 check_nodes
	xcluster_stop
}
##   test [--newver=] upgrade_with_traffic
##     Upgrade K8s while ctraffic is running
test_upgrade_with_traffic() {
	test -n "$__newver" || __newver=master
	tcase "=== k8s-test: upgrade to $__newver with traffic"
	export __newver
	test_start

	otc 201 "ctraffic_start --out=/tmp/ctraffic-ipv4.out -timeout 2m -address 10.0.0.1:5003 -nconn 40 -rate 120"
	otc 201 "ctraffic_start --out=/tmp/ctraffic-ipv6.out -timeout 2m -address [1000::1]:5003 -nconn 40 -rate 120"

	sleep 5
	otc 1 upgrade_master
	sleep 3
	otc 1 "check_namespaces 120"
	
	sleep 5
	local n	
	for n in $(seq 2 $__nvm); do
		otc $n upgrade_worker
	done
	sleep 5
	otc 1 check_nodes

	otc 201 "ctraffic_kill"
	sleep 2
	otc 201 "ctraffic_check /tmp/ctraffic-ipv4.out"
	otc 201 "ctraffic_check /tmp/ctraffic-ipv6.out"

	xcluster_stop
}
##   test ctraffic_pod_restart
##     Restart a POD while ctraffic is running
test_ctraffic_pod_restart() {
	tcase "=== Restart a POD while ctraffic is running"
	test_start $@

	otc 201 "add_srccidr"
	otc 201 "ctraffic_start --out=/tmp/ctraffic-ipv4.out -timeout 15s -address 10.0.0.2:5003 -nconn 40 -rate 80"
	otc 201 "ctraffic_start --out=/tmp/ctraffic-ipv6.out -timeout 15s -address [1000::2]:5003 -nconn 40 -rate 80"

	tcase "Sleep 5 ..."; sleep 5
	otc 1 kill_pod
	tcase "Sleep 8 ..."; sleep 8

	otc 201 "ctraffic_wait --timeout=30"
	otc 201 "ctraffic_check --no-fail /tmp/ctraffic-ipv4.out"
	otc 201 "ctraffic_check --no-fail /tmp/ctraffic-ipv6.out"

	xcluster_stop
}

##   test kube_proxy
##     Test kube-proxy sync
test_kube_proxy() {
	tlog "=== k8s-test: kube-proxy"
	test_start $@
	otc 2 kube_proxy_sync
	otc 2 kube_proxy_restart
	otc 2 kube_proxy_sync
	xcluster_stop
}
##   test setcap
##     Test that get/setcap works in a non-root container
test_setcap() {
	tlog "=== k8s-test: Test that get/setcap works in a non-root container"
	test_start_empty $@
	otc 1 start_alpine_test
	otc 1 check_setcap
	xcluster_stop
}
##   test host_access
##     Test external access to ssh(22) via a VIP address (should NOT work)
test_host_access() {
	tlog "=== k8s-test: Test external access to ssh(22) via a VIP address"
	test_start $@
	otc 201 "negative_access 1000::1"
	otc 201 "negative_access 10.0.0.1"
	xcluster_stop
}
##   test source_ranges
##     Test access to an external service with loadBalancerSourceRanges
test_source_ranges() {
	tlog "=== Test access to an external service with loadBalancerSourceRanges"
	test -n "$__nrouters" || __nrouters=1
	test_start_empty $@
	otc 201 "add_srccidr --ecmp"
	otc 1 source_ranges_start
	otc 201 source_ranges_access
	otc 201 neg_source_ranges_access
	otc 201 "negative_access 1000::8"
	otc 201 "negative_access 10.0.0.8"
	xcluster_stop
}
##   test huge_pages
##     Test huge-pages in a POD
test_huge_pages() {
	tcase "Test huge-pages in a POD"
	test_start_hugep $@
	otcwp mount_hugep
	otc 1 start_hugep
	xcluster_stop
}
##   test udp_over_sync
##     Test that an UDP session over a service survives a kube-proxy sync
##     https://github.com/kubernetes/kubernetes/issues/113802
test_udp_over_sync() {
	tlog "=== Test that an UDP service session survives a kube-proxy sync"
	test_start_empty $@
	otc 1 mserver_udp
	otc 201 "ctraffic_udp -timeout 2m20s -nconn 2"
	xcluster_stop
}
##   test reroute
##     Re-route from one node to another with ctraffic
test_reroute() {
	test_start_mserver2 $@
	otcwp nf_conntrack_tcp_be_liberal
	otcr "set_route 10.0.0.0/24 192.168.1.2"
	otcr "set_route $PREFIX:10.0.0.0/120 $PREFIX:192.168.1.2"
	otc 201 "ctraffic_start --out=/tmp/ctraffic.out -timeout 2m -address 10.0.0.10:5003 -nconn 80 -rate 200"
	tcase "Sleep 10s..."; sleep 10
	otcr "set_route 10.0.0.0/24 192.168.1.3"
	otcr "set_route $PREFIX:10.0.0.0/120 $PREFIX:192.168.1.3"
	tcase "Sleep 10s..."; sleep 10
	otc 201 ctraffic_kill
	otc 201 "ctraffic_check --no-fail /tmp/ctraffic.out"
	xcluster_stop
}
##   test big_cluster [--pods-per-node=4]
##     Use --nvm=N to create a big cluster. Nx4 Mserver PODs will be
##     deployed.
test_big_cluster() {
	test -n "$__nrouters" || export __nrouters=1
	test -n "$__nvm" || export __nvm=20
	test -n "$__pods_per_node" || __pods_per_node=4
	export xcluster_PREFIX=$PREFIX
	test_start_empty $@
	otcwp conntrack_size
	otcr "conntrack_size 40000"
	local targets=$((__nvm * __pods_per_node))
	local nconn=$((targets * 25))
	otc 1 "mserver2 $targets"
	otc 201 "xmconnect 10.0.0.10 $nconn $targets 60"
	xcluster_stop
}

. $($XCLUSTER ovld test)/default/usr/lib/xctest
indent=''
. /etc/profile

##
# Get the command
cmd=$1
shift
grep -q "^cmd_$cmd()" $0 $hook || die "Invalid command [$cmd]"

while echo "$1" | grep -q '^--'; do
    if echo $1 | grep -q =; then
	o=$(echo "$1" | cut -d= -f1 | sed -e 's,-,_,g')
	v=$(echo "$1" | cut -d= -f2-)
	eval "$o=\"$v\""
    else
	o=$(echo "$1" | sed -e 's,-,_,g')
	eval "$o=yes"
    fi
    shift
done
unset o v
long_opts=`set | grep '^__' | cut -d= -f1`

# Execute command
trap "die Interrupted" INT TERM
cmd_$cmd "$@"
status=$?
rm -rf $tmp
exit $status
