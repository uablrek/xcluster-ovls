#! /bin/sh
##
## k8s-ha.sh --
##
##   Help script for the xcluster ovl/k8s-ha.
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

## Commands;
##

##   env
##     Print environment.
cmd_env() {
	test -n "$xcluster_ETCD_VMS" || xcluster_ETCD_VMS="193"
	export xcluster_ETCD_VMS
	test -n "$__cni" || __cni=bridge
	if test "$cmd" = "env"; then
		opts="cni|nvm"
		set | grep -E "^(__($opts)|xcluster_ETCD_VMS)="
		return 0
	fi

	test -n "$xcluster_DOMAIN" || xcluster_DOMAIN=xcluster
	test -n "$XCLUSTER" || die 'Not set [$XCLUSTER]'
	test -x "$XCLUSTER" || die "Not executable [$XCLUSTER]"
	eval $($XCLUSTER env)
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
##   test start_empty [--cni=bridge]
##     Start empty cluster
test_start_empty() {
	cd $dir
	export __image=$XCLUSTER_HOME/hd-k8s-xcluster.img
	test -n "$__nrouters" || export __nrouters=1
	if test -n "$TOPOLOGY"; then
		tlog "Using TOPOLOGY=$TOPOLOGY"
		. $($XCLUSTER ovld network-topology)/$TOPOLOGY/Envsettings
	fi
	export xcluster___cni=$__cni
	xcluster_start network-topology k8s-cni-$__cni . $@
}
##   test start
##     Start cluster
test_start() {
	test $__nvm -lt 3 && die "Must have >=3 VMs"
	test_start_empty $@
	$XCLUSTER scaleout $xcluster_ETCD_VMS
	tcase "VM connectivity; $xcluster_ETCD_VMS"
	tex check_vm $xcluster_ETCD_VMS || tdie
	if test "$xcluster_K8S_DISABLE" != "yes"; then
		otc 1 check_namespaces
		otc 1 check_nodes
		otcr vip_routes
	fi
}

##
test -n "$__nvm" || export __nvm=7    # 3 masters + 4 workers
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
