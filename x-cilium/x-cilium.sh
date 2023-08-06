#! /bin/sh
##
## x-cilium.sh --
##
##   Help script for the xcluster ovl/x-cilium.
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
	echo "$prg: $*" >&2
}
dbg() {
	test -n "$__verbose" && echo "$prg: $*" >&2
}

##   env
##     Print environment.
cmd_env() {
	test "envread" = "yes" && return 0
	envread=yes

	test -n "$__ciliumd" || __ciliumd=$GOPATH/src/github.com/cilium/cilium
	if test "$cmd" = "env"; then
		set | grep -E '^(__.*)='
		return 0
	fi

	test -d "$__ciliumd" || die "Not a directory [$__ciliumd]"
	test -n "$xcluster_DOMAIN" || xcluster_DOMAIN=xcluster
	test -n "$XCLUSTER" || die 'Not set [$XCLUSTER]'
	test -x "$XCLUSTER" || die "Not executable [$XCLUSTER]"
	images=$($XCLUSTER ovld images)/images.sh
	test -x $images || die "Not executable [$images]"
	eval $($XCLUSTER env)
}
##   build
##     Build cilium images
cmd_build() {
	cmd_env
	cd "$__ciliumd"
	git clean -dxf
	make clean
	make precheck || die "make precheck"
	#make build || die "make build"
	make docker-cilium-image docker-operator-generic-image || die "make images"
}
##   generate_manifest
##     Generate the Cilium manifest using Helm
cmd_generate_manifest() {
	cmd_env
	cd "$__ciliumd/install/kubernetes"
	helm template cilium \
		--namespace kube-system \
		--set devices=eth1 \
		--set containerRuntime.integration=crio \
		--set kubeProxyReplacement=strict \
		--set k8sServiceHost=192.168.1.1 \
		--set k8sServicePort=6443 \
		--set ipv6.enabled=true \
		--set operator.replicas=1 \
		--set ipam.mode=kubernetes \
		--set securityContext.privileged=true \
		--set bpf.masquerade=false \
		--set nativeRoutingCIDR=11.0.0.0/16 \
		| sed -e 's,-ci:latest,:latest,' \
		| sed -E 's,quay.io/cilium/cilium:[^"]+,quay.io/cilium/cilium:latest,' \
		| sed -E 's,quay.io/cilium/operator-generic:[^"]+,quay.io/cilium/operator-generic:latest,' \
		> $dir/default/etc/kubernetes/load/quick-install.yaml \
		|| die "Generate manifest"
}
##   precheck_fails
##     Exit OK if "make precheck" fails!! This is intended to be used
##     to find the first working precheck using git bisect
cmd_precheck_fails() {
	local commit log=/tmp/$USER/xcluster/cilium-test.log
	cmd_env
	cd $__ciliumd
	commit=$(git rev-parse --short HEAD)
	git clean -dxf
	if make precheck; then
		echo "Precheck works $commit" >> $log
		die "Precheck works"
	fi
	echo "Precheck fails $commit" >> $log
	return 0
}
##   build_and_test
##     Build images on the current commit and check.
##     This should be used with "git bisect"
cmd_build_and_test() {
	local tstart now commit log=/tmp/$USER/xcluster/cilium-test.log
	cmd_env
	cd $__ciliumd
	commit=$(git rev-parse --short HEAD)
	tstart=$(date +%s)
	cmd_build
	cmd_generate_manifest
	cd $dir
	$images lreg_upload quay.io/cilium/cilium:latest || die lreg_upload
	$images lreg_upload quay.io/cilium/operator-generic:latest || die lreg_upload
	mkdir -p $(dirname $log)
	if ! $me test basic > /dev/null; then
		$XCLUSTER stop
		now=$(date +%s)
		echo "bad  $commit" >> $log
		die "FAILED after $((now - tstart)) sec"
	fi
	now=$(date +%s)
	echo "good $commit" >> $log
	log "SUCCESS after $((now - tstart)) sec"
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
		test_basic
	fi		

	now=$(date +%s)
	tlog "Xcluster test ended. Total time $((now-begin)) sec"
}
##   test start_empty
##     Start empty cluster
test_start_empty() {
	cd $dir
	export __image=$XCLUSTER_HOME/hd-k8s-xcluster.img
	export xcluster_PROXY_MODE=disabled
	export __mem=2048
	export __mem1=$((__mem + 512))
	test -n "$__nrouters" || export __nrouters=1
	export xcluster_PREFIX=$PREFIX
	if test -n "$TOPOLOGY"; then
		tlog "Using TOPOLOGY=$TOPOLOGY"
		. $($XCLUSTER ovld network-topology)/$TOPOLOGY/Envsettings
	fi
	xcluster_start network-topology . $@
	otc 1 check_namespaces
	otc 1 check_nodes
	otcr vip_routes
}
##   test start
##     Start cluster with ovl functions
test_start() {
	test -n "$__nrouters" || export __nrouters=1
	test_start_empty $@
	otc 1 start_servers
}
##   test basic (default)
##     Test communication from a node
test_basic() {
	test_start $@
	otc 2 "mconnect 10.0.0.0"
	otc 2 "mconnect alpine.default.svc.xcluster"
	xcluster_stop
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
