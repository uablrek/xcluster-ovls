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
	test -n "$PREFIX" || PREFIX=fd00:
	test -n "$__nvm" || __nvm=4
	test -n "$__nrouters" || __nrouters=1
	test -n "$__registry" || __registry=docker.io/uablrek
	test -n "$__replicas" || __replicas=4
	test -n "$KUBERNETESD" || KUBERNETESD=$HOME/tmp/kubernetes
	if test "$cmd" = "env"; then
		local opt="registry|nvm|nrouters|replicas"
		set | grep -E "^(__($opt)|KUBERNETESD)="
		return 0
	fi

	images=$($XCLUSTER ovld images)/images.sh
	test -n "$xcluster_DOMAIN" || export xcluster_DOMAIN=xcluster
	test -n "$xcluster_PROXY_MODE" || export xcluster_PROXY_MODE=ipvs
	test -n "$XCLUSTER" || die 'Not set [$XCLUSTER]'
	test -x "$XCLUSTER" || die "Not executable [$XCLUSTER]"
	eval $($XCLUSTER env)
	if echo "$xcluster_PROXY_MODE" | grep -q nftables; then
		tlog "Set feature-gate [NFTablesProxyMode=true]"
		export xcluster_FEATURE_GATES=NFTablesProxyMode=true
	fi
	export xcluster_PREFIX=$PREFIX
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
##   build_sctpt
##     Build the "sctpt" utility
cmd_build_sctpt() {
	cmd_env
	local d=$($XCLUSTER ovld sctp)
	make -j$(nproc) -C $d/src || die make
}
##
##   test [--xterm] [--no-stop] [test x-ovls...] > logfile
##     Exec tests
cmd_test() {
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
		test_default
	fi		

	now=$(date +%s)
	tlog "Xcluster test ended. Total time $((now-begin)) sec"
}

##   test [--hugep] [--wait] start_empty
##     Start cluster without servers
test_start_empty() {
	test "$__no_start" = "yes" && return 0
	if test -n "$TOPOLOGY"; then
		tlog "WARNING: network-topology [$TOPOLOGY]"
		export xcluster_TOPOLOGY=$TOPOLOGY
		. $($XCLUSTER ovld network-topology)/$TOPOLOGY/Envsettings
	fi
	if test "$__hugep" = "yes"; then
		local n
		for n in $(seq $FIRST_WORKER $__nvm); do
			eval export __append$n="hugepages=128"
		done
	fi
	local cni
	if test -n "$__cni"; then
		# CI in Jenkins requires a --cni parameter
		echo $@ | grep -q "k8s-cni-$__cni" || cni=k8s-cni-$__cni
	fi
	if echo $@ $cni | grep -q cilium; then
		__cni=cilium
		export __mem=$((__mem + 1024))
		export __mem1=$((__mem1 + 1024))
		test -n "$xcluster_PROXY_MODE" || export xcluster_PROXY_MODE=disabled
	fi
	if echo $@ $cni | grep -q calico; then
		__cni=calico
		export __mem=$((__mem + 512))
		export __mem1=$((__mem1 + 512))
	fi
	xcluster_start network-topology . $cni $@
	test "$__hugep" = "yes" && otcwp mount_hugep
	otc 1 check_namespaces
	otc 1 check_nodes
	test "$__wait" = "yes" && otc 1 wait
}
##   test [--multus] start
##     Start cluster and tserver deployment
test_start() {
	test "$__no_start" = "yes" && return 0
	test_start_empty $@
	if test "$__multus" = "yes"; then
		tcase "Installing Multus"
		kubectl apply -f $($XCLUSTER ovld multus)/multus-install.yaml
	fi
	otc 1 "svc tserver 10.0.0.0"
	otc 1 "deployment --replicas=$__replicas tserver"
}
##   test default
##     The default test suite, used in CI
test_default() {
	__replicas=4
	__nvm=4
	__nrouters=1
	__hugep=yes
	__wait=yes
	test_start $@
	__no_start=yes
	__no_stop=yes
	
	test_basic
	test_mconnect
	test_connectivity
	#test "$xcluster_PROXY_MODE" = "ipvs" && __multiport=yes # flakey!
	case "$__cni" in
		cilium) __count=40;;
		antrea) __count=20;;
		calico) __count=30;;
		*) __count=80
	esac
	test_affinity

	unset __no_stop
	xcluster_stop
}
##   test basic
##     Basic K8s tests
test_basic() {
	__hugep=yes
	test_start $@
	otc 1 "nslookup www.google.se"
	otc 1 "nslookup tserver.default.svc.$xcluster_DOMAIN"
	otc 1 "svc headless"
	otc 1 "svc headless-hostnet"
	otc 1 "daemonset tserver-daemonset"
	otc 1 "daemonset tserver-hostnet"
	otc 1 "daemonset alpine-hugep"
	otc 1 podip
	otc 1 headless_services
	xcluster_stop
}
##   test scale
##     Scale a daemonset
test_scale() {
	test_start $@
	otc 1 "scale tserver $((__replicas + 4))"
	otc 1 "scale tserver $__replicas"
	xcluster_stop
}
##   test [--no-ecmp] [--margin=] mconnect
##     Simple external mconnect. --narrow routes to vm-002 only
test_mconnect() {
	test_start $@
	if test "$__no_ecmp" = "yes"; then
		otcr "vip_routes 192.168.1.2"
	else
		otcr "vip_routes"
	fi
	local nconn=$((__replicas * 25))
	otc 201 "mconnect 10.0.0.0 $nconn $__replicas"
	otc 201 "mconnect $PREFIX:10.0.0.0 $nconn $__replicas"
	xcluster_stop
}
##   test connectivity
##     Connectivity test
test_connectivity() {
	test_start $@
	otc 1 "svc lbrange 10.0.0.1"
	otc 1 "svc tserver-plus 10.0.0.3"
	otc 1 "svc hostnet"
	otc 1 "daemonset tserver-hostnet"
	otcr vip_routes
	local nconn=$((__replicas * 25))
	# Use DN from main netns and from PODs
	otc 2 "mconnect tserver.default.svc.$xcluster_DOMAIN $nconn $__replicas"
	otc 2 "mconnect --pod=app=tserver tserver $nconn $__replicas"
	otc 2 "mconnect --pod=app=tserver-hostnet tserver $nconn $__replicas"
	otc 2 "mconnect hostnet.default.svc.$xcluster_DOMAIN"
	otc 2 "mconnect --pod=app=tserver hostnet $nconn $__replicas"
	otc 2 "mconnect --pod=app=tserver-hostnet hostnet $nconn $__replicas"
	# Use LBIP from within a POD
	otc 2 "mconnect --pod=app=tserver 10.0.0.0 $nconn $__replicas"
	otc 2 "mconnect --pod=app=tserver $PREFIX:10.0.0.0 $nconn $__replicas"
	# Security
	otc 201 "negative_access 10.0.0.0"
	otc 201 "negative_access $PREFIX:10.0.0.0"
	# loadBalancerSourceRanges
	otc 201 "mconnect 10.0.0.1 $nconn $__replicas"
	otc 201 "mconnect $PREFIX:10.0.0.1 $nconn $__replicas"
	otc 201 "neg_source_ranges_access 10.0.0.1"
	# ExternalIPs
	if test "$__cni" != "cilium"; then
		otc 201 "mconnect --udp 10.0.0.35 $nconn $__replicas"
		otc 201 "mconnect --udp $PREFIX:10.0.0.35 $nconn $__replicas"
		otc 2 "mconnect --pod=app=tserver 10.0.0.35 $nconn $__replicas"
		otc 2 "mconnect --pod=app=tserver $PREFIX:10.0.0.35 $nconn $__replicas"
	else
		# Some connect fails to ExternalIPs, but works to ClusterIP
		# and loadBalancerIP?!
		tlog "WARNING: ExternalIPs test sipped for cni=cilium"
	fi
	# UDP
	otc 201 "mconnect --udp 10.0.0.3 $nconn $__replicas"
	otc 201 "mconnect --udp $PREFIX:10.0.0.3 $nconn $__replicas"
	otc 2 "mconnect --udp --pod=app=tserver tserver-plus $nconn $__replicas"
	# SCTP
	if test "$__cni" != "cilium"; then
		otc 201 "sctp 10.0.0.3"
		if echo "$__cni" | grep -qE 'calico|antrea|flannel'; then
			tlog "WARNING: SCTP from POD sipped for calico+antrea+flannel"
		else
			otc 2 "sctp --pod=app=tserver tserver-plus"
		fi
	else
		tlog "WARNING: SCTP test sipped for cni=cilium"
	fi
	# Outgoing connect. Will test both IPv4 and IPv6
	otc 1 outgoing_http
	xcluster_stop
}
##   test [--multiport] [--count=] affinity
##     Test Service session affinity
test_affinity() {
	__nrouters=1
	test_start $@
	otc 1 "svc tserver-affinity 10.0.0.33"
	otc 201 "vip_routes 192.168.1.2"
	otc 201 add_srccidr
	otc 201 "affinity --multiport=$__multiport --count=$__count 10.0.0.33"
	otc 201 "affinity --multiport=$__multiport --count=$__count $PREFIX:10.0.0.33"
	xcluster_stop
}
##   test [--newver=] upgrade
##     Test K8s upgrade
test_upgrade() {
	test -n "$__newver" || __newver=master
	export __newver
	tlog "=== k8s-test: Upgrade to $__newver"
	test_start_empty $@
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
	test_start_empty $@
	otc 1 "daemonset alpine-test"
	otc 1 check_setcap
	xcluster_stop
}
##   test host_access
##     Test external access to ssh(22) via a VIP address (should NOT work)
test_host_access() {
	tlog "=== k8s-test: Test external access to ssh(22) via a VIP address"
	test_start $@
	otc 201 "negative_access $PREFIX:10.0.0.0"
	otc 201 "negative_access 10.0.0.0"
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

test -z "$__nvm" && __nvm=X
. $($XCLUSTER ovld test)/default/usr/lib/xctest
test "$__nvm" = "X" && unset __nvm

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
