#! /bin/sh
##
## k8s-gateway-api.sh --
##
##   Help script for the xcluster ovl/k8s-gateway-api.
##

prg=$(basename $0)
dir=$(dirname $0); dir=$(readlink -f $dir)
me=$dir/$prg
tmp=/tmp/${prg}_$$
test -n "$PREFIX" || PREFIX=1000::1

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
	echo "$*" >&2
}
dbg() {
	test -n "$__verbose" && echo "$prg: $*" >&2
}

##   env
##     Print environment.
cmd_env() {
	test "envread" = "yes" && return 0
	envread=yes

	test -n "$__ver" || __ver=v1.0.0
	test -n "$__ciliumd" || __ciliumd=$GOPATH/src/github.com/cilium/cilium
	test -n "$__stability" || __stability=experimental
	if test "$cmd" = "env"; then
		local opt='ciliumd|ver|stability'
		set | grep -E "^__($opt)|^PREFIX="
		return 0
	fi
	
	test -n "$xcluster_DOMAIN" || xcluster_DOMAIN=xcluster
	test -n "$XCLUSTER" || die 'Not set [$XCLUSTER]'
	test -x "$XCLUSTER" || die "Not executable [$XCLUSTER]"
	eval $($XCLUSTER env)
}
##   generate_cilium_manifest
##     Generate the Cilium manifest using Helm
cmd_generate_cilium_manifest() {
	cmd_env
	cd "$__ciliumd/install/kubernetes" || die "No Cilium clone?"
	helm template cilium \
		--namespace kube-system \
		--set devices=eth1 \
		--set containerRuntime.integration=crio \
		--set kubeProxyReplacement=strict \
		--set k8sServiceHost=192.168.1.1 \
		--set k8sServicePort=6443 \
		--set ipv6.enabled=true \
		--set operator.replicas=1 \
		--set gatewayAPI.enabled=true \
		--set ipam.mode=kubernetes \
		--set securityContext.privileged=true \
		--set bpf.masquerade=false \
		--set nativeRoutingCIDR=11.0.0.0/16 \
		> $dir/default/etc/kubernetes/cilium-install.yaml \
		|| die "Generate manifest"
}
##   get_nginx_manifests
##     Get the nginx-gateway-fabric manifests
cmd_get_nginx_manifests() {
	cmd_env
	local src=$GOPATH/src/github.com/nginxinc/nginx-gateway-fabric/deploy/manifests
	test -d $src || die "Not cloned"
	local dst=$dir/nginx-gateway-fabric/etc/kubernets/nginx-gateway-fabric
	rm -rf $dst; mkdir -p $dst
	cp -r $src/nginx-gateway.yaml $src/crds $dst
}
##   get_manifests [--ver=]
##     Download the "standard" and "experimental" inatall manifetsts
cmd_get_manifests() {
	cmd_env
	log "Get manifests for [$__ver]"
	local url=https://github.com/kubernetes-sigs/gateway-api/releases/download/$__ver
	local dst=$dir/default/etc/kubernetes
	local s
	for s in standard experimental; do
		curl -sL $url/$s-install.yaml > $dst/$s-install.yaml || die
	done
	curl -sL $url/webhook-install.yaml > $dst/webhook-install.yaml
}

##
## Tests;
##   test [--xterm] [--no-stop] test <test-name>  [ovls...] > $log
##   test [--xterm] [--no-stop] > $log   # default test
##     Exec tests
##
cmd_test() {
	cmd_env
	start=starts
	test "$__xterm" = "yes" && start=start
	rm -f $XCLUSTER_TMP/cdrom.iso

	if test -n "$1"; then
		local t=$1
		shift
		test_$t $@
	else
		test_start
	fi		

	now=$(date +%s)
	tlog "Xcluster test ended. Total time $((now-begin)) sec"
}
##   test start_empty
##     Start empty cluster
test_start_empty() {
	cd $dir
	test -n "$__nrouters" || export __nrouters=1
	xcluster_start network-topology k8s-pv . $@
	otc 1 check_namespaces
	otc 1 check_nodes
	otcr vip_routes
}
##   test start
##     Start cluster with ovl functions
test_start() {
	test -n "$__nrouters" || export __nrouters=1
	test_start_empty $@
	otc 1 "install $__stability"
}
##   test start_nginx
##     Start with nginx-gateway-fabric
test_start_nginx() {
	test -d $dir/nginx-gateway-fabric || tdie "No manifests"
	test_start $@
	otc 1 "install_nginx"
}

##
. $($XCLUSTER ovld test)/default/usr/lib/xctest
indent=''

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
