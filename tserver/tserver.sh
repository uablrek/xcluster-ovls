#! /bin/sh
##
## tserver.sh --
##
##   Help script for the xcluster ovl/tserver.
##

prg=$(basename $0)
dir=$(dirname $0); dir=$(readlink -f $dir)
me=$dir/$prg
tmp=/tmp/${prg}_$$
test -n "$PREFIX" || PREFIX=fd00:

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
findf() {
	f=$ARCHIVE/$1
	test -r $f || f=$HOME/Downloads/$1
	test -r $f || die "Not found [$1]"
}

## Commands;
##

##   env
##     Print environment.
cmd_env() {

	test -n "$__tag" || __tag="docker.io/uablrek/tserver:latest"
	
	if test "$cmd" = "env"; then
		set | grep -E '^(__.*)='
		return 0
	fi

	test -n "$xcluster_DOMAIN" || xcluster_DOMAIN=xcluster
	test -n "$XCLUSTER" || die 'Not set [$XCLUSTER]'
	test -x "$XCLUSTER" || die "Not executable [$XCLUSTER]"
	eval $($XCLUSTER env)
}
##   mkimage [--upload] [--tag=docker.io/uablrek/tserver:latest]
##     Create the docker image (requires xcluster). Optionally upload
##     to the local registry
cmd_mkimage() {
	cmd_env
	local imagesd=$($XCLUSTER ovld images)
	$imagesd/images.sh mkimage --force --upload=$__upload --tag=$__tag $dir/image
}
##   install_servers <dst>
##     Install mconnect, ctraffic, kahttp servers. The sctpt setver is
##     installed if it's in the path
cmd_install_servers() {
	test -n "$1" || die "No destination dir"
	local dst="$1"
	if ! test -d "$dst"; then
		test -e "$dst" && die "Not a directory [$dst]"
		mkdir -p "$dst" || die "Mkdir failed [$dst]"
	fi

	local d=$GOPATH/src/github.com/Nordix/kahttp
	test -d $d || die "Not a directory [$d]"

	local p
	for p in mconnect kahttp; do
		findf $p.xz
		xz -dc $f > $dst/$p
		chmod a+x $dst/$p
	done
	cp -r $d/image/etc/cert $dst

	p=ctraffic
	findf $p.gz
	gzip -dc $f > $dst/$p
	chmod a+x $dst/$p
	if which sctpt > /dev/null; then
		log "Installing sctpt ..."
		cp $(which sctpt) $dst
	else
		log "Not available: sctpt"
	fi

	which musl-gcc > /dev/null || die "Install musl-tools"
	mkdir -p $tmp
	make -C $dir/src O=$tmp CC=musl-gcc static > /dev/null || die "Make failed"
	cp $tmp/bin/tserver $dst
}
##
## Tests;
##   test [--xterm] [--no-stop] [test] [ovls...] > logfile
##     Exec tests
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
		test_connectivity
	fi		

	now=$(date +%s)
	tlog "Xcluster test ended. Total time $((now-begin)) sec"
}
##   test start_empty
##     Start empty cluster
test_start_empty() {
	cd $dir
	test -n "$__nrouters" || __nrouters=1
	export xcluster_PREFIX=$PREFIX
	xcluster_start . $@
	otc 1 check_namespaces
	otc 1 check_nodes
	otcr vip_routes
}
##   test start [--replicas=4]
##     Start cluster with ovl functions
test_start() {
	test_start_empty $@
	otcwp conntrack_size
	test -n "$__replicas" || __replicas=4
	local ctsize=$((__replicas * 4000 + 20000))
	otcr "conntrack_size $ctsize"
	otc 1 "start_tserver --replicas=$__replicas"
}
##   test start_narrow_svc [--replicas=4]
##     Start cluster with svc's and VIP route to vm-002
test_start_narrow_svc() {
	test_start $@
	otc 1 create_svc
	otcr "vip_route 192.168.1.2"
}
##   test start_daemonset
##     Start with a DaemonSet and a externalTrafficPolicy:Local svc
test_start_daemonset() {
	test_start_empty $@
	otcr "vip_route 192.168.1.2"
	otc 1 "create_1svc etp-local 10.0.0.60"
	otc 1 "start_daemonset"
}
##   test [--cni=bridge] start_cni
##     Start with a selected CNI-plugin
test_start_cni() {
	test -n "$__cni" || __cni=bridge
	export xcluster___cni=$__cni
	export __image=$XCLUSTER_HOME/hd-k8s-xcluster.img
	test_start_empty k8s-cni-$__cni $@
}
##   test antrea
##     A custom test of distribution to an IPv6 service from within a POD
test_antrea() {
	test -n "$__cni" || __cni=antrea
	test_start_cni $@
	otc 1 antrea_setup
	otc 1 "traffic_from_pod app=tserver-mconnect tserver-mconnect"
}
##   test connectivity [--replicas=4] (default)
##     Test external connectivity
test_connectivity() {
	test_start $@
	otc 1 create_svc
	otc 201 "traffic --replicas=$__replicas 10.0.0.52"
	xcluster_stop
}
##   test lb_sourceranges
##     Test to resrict external access using loadBalancerSourceRanges
test_lb_sourceranges() {
	tlog "=== Test to resrict external access using loadBalancerSourceRanges"
	# "fd00:" is used in the svc manifest and we need a tester
	__ntesters=1
	test_start $@
	otcr "vip_route 192.168.1.2"
	otc 1 "create_1svc lb-sourceranges 10.0.0.10"
	otc 221 "traffic --replicas=$__replicas 10.0.0.10"
	otc 201 "deny_external_traffic 10.0.0.10"
	otc 2 "traffic --replicas=$__replicas lb-sourceranges.default.svc.xcluster"
	otc 2 "deny_external_traffic 10.0.0.10"
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
