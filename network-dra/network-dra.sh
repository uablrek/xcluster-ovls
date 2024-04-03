#! /bin/sh
##
## network-dra.sh --
##
##   Help script for the xcluster ovl/network-dra.
##
prg=$(basename $0)
dir=$(dirname $0); dir=$(readlink -f $dir)
me=$dir/$prg
tmp=/tmp/${prg}_$$

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

## Commands;
##

##   env
##     Print environment.
cmd_env() {
	test -n "$__nvm" || __nvm=2
	test -n "$__nrouters" || __nrouters=1
	test -n "$xcluster_API_FLAGS" || xcluster_API_FLAGS="--runtime-config=resource.k8s.io/v1alpha2=true"
	export xcluster_FEATURE_GATES=DynamicResourceAllocation=true
	test -n "$KIND_NAME" || KIND_NAME=network-dra
	test -n "$KIND_CONFIG" || KIND_CONFIG=$dir/config/kind-$KIND_NAME.yaml
	test -n "$NETWORK_DRA_DIR" || NETWORK_DRA_DIR=$GOPATH/src/github.com/LionelJouin/network-dra
	S=$NETWORK_DRA_DIR

	if test "$cmd" = "env"; then
		local opt="nvm|nrouters|log"
		set | grep -E "^(__($opt)|xcluster_.*|NETWORK_DRA.*|KIND_.*)="
		exit 0
	fi

	test -n "$XCLUSTER" || die 'Not set [$XCLUSTER]'
	test -x "$XCLUSTER" || die "Not executable [$XCLUSTER]"
	eval $($XCLUSTER env)
	images=$($XCLUSTER ovld images)/images.sh
}
##   manifests [--clean]
##     Download and refresh manifests
cmd_manifests() {
	local base_url=https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master
	local dst=$dir/default/etc/kubernetes/network-dra
	local f=multus-daemonset-thick.yml
	test -r $dst/$f -a "$__clean" != "yes" \
		|| curl -L $base_url/deployments/$f > $dst/$f
	if test "$__clean" = "yes" -o ! -r $dst/network-dra.yaml; then
		cd $S
		f=$dst/network-dra.yaml
		helm template network-dra deployments/network-DRA > $f
		sed -i -e 's,localhost:5000/network-dra/,example.com/,' $f
	fi
}
##   images [--force]
##     Load images to the private reg
cmd_images() {
	local i
	for i in $(grep -rhF image: default | sed -e 's,.*image: *,,' | sort -u); do
		echo $i | grep -q network-dra && continue
		if test "$__force" = "yes"; then
			$images lreg_cache $i
		else
			$images lreg_isloaded $i || $images lreg_cache $i
		fi
	done
}
##   build
##     Build the network-dra images, and upload to private registry
cmd_build() {
	cd $S
	make BUILD_STEPS="build tag" BUILD_REGISTRY=example.com/ || die make
	$images lreg_upload example.com/network-dra-controller:latest
	$images lreg_upload example.com/network-dra-plugin:latest
}

##
##   test [--log=]   # Execute default tests
##   test [--log=] [--xterm] [--no-stop] <test-suite> [ovls...] > logfile
##     Exec tests
cmd_test() {
	start=starts
	test "$__xterm" = "yes" && start=start
	rm -f $XCLUSTER_TMP/cdrom.iso

	local t=pod
	if test -n "$1"; then
		local t=$1
		shift
	fi		

	if test -n "$__log"; then
		date > $__log || die "Can't write to log [$__log]"
		test_$t $@ >> $__log
	else
		test_$t $@
	fi

	now=$(date +%s)
	log "Xcluster test ended. Total time $((now-begin)) sec"
}
##   kind
##   kind --stop
##     Start or stop the KinD cluster
cmd_kind() {
	kind delete cluster --name $KIND_NAME
	test "$__stop" = "yes" && return 0
	kind create cluster --name $KIND_NAME --config $KIND_CONFIG $@ || die
}

##   test [--wait] start_empty
##     Start empty cluster
test_start_empty() {
	cd $dir
	if test -n "$TOPOLOGY"; then
		tlog "Using TOPOLOGY=$TOPOLOGY"
		. $($XCLUSTER ovld network-topology)/$TOPOLOGY/Envsettings
	fi
	export xcluster_API_FLAGS
	xcluster_start network-topology containerd . $@
	otc 1 check_namespaces
	otc 1 check_nodes
	test "$__wait" = "yes" && otc 1 wait
}
##   test start
##     Start cluster and install multus and network-dra
test_start() {
	test_start_empty $@
	tcase "Taint the master node [vm-001]"
	kubectl label nodes vm-001 node-role.kubernetes.io/control-plane=''
	kubectl taint nodes vm-001 node-role.kubernetes.io/control-plane:NoSchedule
	otc 1 multus
	otc 1 network_dra
}
##   test pod
##     Start a POD with an additional interface
test_pod() {
	__wait=yes
	test_start $@
	otc 1 "start_pod demo-a"
	xcluster_stop
}

##
# The "__nvm=X" is a work-around to prevent the "xctest" lib to set
# __nvm=4 as default. We want to set the default in the cmd_env() function.
test -z "$__nvm" && __nvm=X
. $($XCLUSTER ovld test)/default/usr/lib/xctest
test "$__nvm" = "X" && unset __nvm
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
	elif test "$1" = "--"; then
		shift
		break
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
cmd_env
cd $dir
cmd_$cmd "$@"
status=$?
rm -rf $tmp
exit $status
