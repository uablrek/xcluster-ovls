#! /bin/sh
##
## k8s-ha.sh --
##
##   Help script for the xcluster ovl/k8s-ha.
##
## Env:
##   # Defaults shown
##   xcluster_BASE_FAMILY=IPv4
##   xcluster_ETCD_FAMILY=IPv4
##   xcluster_K8S_DISABLE=no
##   xcluster_ETCD_FAMILY=IPv4
##   xcluster_ETCD_VMS="193 194 195"
##   xcluster_LB_VMS="191 192"
##   xcluster_MASTERS="vm-001,vm-002,vm-003"
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
findf() {
	f=$ARCHIVE/$1
	test -r $f && return 0
	f=$HOME/Downloads/$1
	test -r $f
}

## Commands:
##   env
##     Print environment.
cmd_env() {
	test -n "$xcluster_MASTERS" || export xcluster_MASTERS=vm-001,vm-002,vm-003
	test -n "$xcluster_ETCD_VMS" || export xcluster_ETCD_VMS="193 194 195"
	etcd_size=$(echo $xcluster_ETCD_VMS | wc -w)
	test -n "$xcluster_LB_VMS" || export xcluster_LB_VMS="191 192"
	test -n "$XCLUSTER_MONITOR_BASE" || XCLUSTER_MONITOR_BASE=4000
	export xcluster_ETCD_VMS
	test -n "$__cni" || __cni=bridge
	test -n "$__keepalived_ver" || __keepalived_ver=2.2.8

	# This is a cludge to fix the (silly) default __nvm=4 in the test env
	test "$__nvm" = "X" && unset __nvm

	if test "$cmd" = "env"; then
		opts="cni|nvm|keepalived_ver"
		xvar="MASTERS|ETCD_VMS|K8S_DISABLE|LB_VMS|ETCD_FAMILY"
		set | grep -E "^(__($opts)|xcluster_($xvar))="
		return 0
	fi

	test -n "$xcluster_DOMAIN" || xcluster_DOMAIN=xcluster
	test -n "$XCLUSTER" || die 'Not set [$XCLUSTER]'
	test -x "$XCLUSTER" || die "Not executable [$XCLUSTER]"
	eval $($XCLUSTER env)
}
##   keepalived <--download|--unpack|--build> [--force]
##   keepalived --install=dir
##   keepalived --man [page]
##     Handle keepalived
cmd_keepalived() {
	cmd_env
	test "$__build" = "yes" && __unpack=yes
	test "$__unpack" = "yes" &&  __download=yes

	local d=$XCLUSTER_WORKSPACE/keepalived-$__keepalived_ver
	local x=$d/sys/usr/local/sbin/keepalived
	local ar=keepalived-$__keepalived_ver.tar.gz

	if test "$__man" = "yes"; then
		MANPATH="$d/sys/usr/local/share/man"
		test -d "$MANPATH" || die "Keepalived not built"
		if test -n "$1"; then
			export MANPATH
			xterm -bg '#ddd' -fg '#222' -geometry 80x43 -T $1 -e man $1 &
		else
			local f
			mkdir -p $tmp
			for f in $(find $MANPATH/ -type f); do
				basename $f >> $tmp/man
			done
			cat $tmp/man | sort | column
		fi
		return 0
	fi

	if test -n "$__install"; then
		if test -x $x; then
			mkdir -p "$__install" || die "Can't create install dir"
			cp $x $__install
		else
			log "Keepalived not built"
		fi
		return 0
	fi

	if test "$__download" = "yes"; then
		local ar
		if ! findf $ar; then
			curl -L https://www.keepalived.org/software/$ar \
				> $ARCHIVE/$ar || die "Download failed"
		fi
	fi

	if test "$__unpack" = "yes"; then
		test "$__force" = "yes" && rm -rf $d
		if ! test -d $d; then
			findf keepalived-$__keepalived_ver.tar.gz || die "Not downloaded"
			tar -C $XCLUSTER_WORKSPACE -xf $f || die "Unpack failed"
			test -d $d || die "Unexpected dir"
		fi
	fi

	if test "$__build" = "yes"; then
		if ! test -d $d/sys; then
			cd $d
			./configure --disable-systemd || die configure
			make -j$(nproc) || die make
			make DESTDIR=$d/sys install || die "make install"
			test -x $x || die "Not executable [$x]"
		fi
	fi
}

##   stop_vm <vm>
##     Stop VM emulation
cmd_stop_vm() {
	test -n "$1" || die "No VM"
	cmd_env
	local vm=$1
	rsh $vm sync
	local port=$((XCLUSTER_MONITOR_BASE + vm))
	echo stop | nc -N localhost $port > /dev/null 2>&1
}
##   reset_vm <vm>
##     Reset and continue VM emulation
cmd_reset_vm() {
	test -n "$1" || die "No VM"
	cmd_env
	local vm=$1
	local port=$((XCLUSTER_MONITOR_BASE + vm))
	echo "system_reset\rcont" | nc -N localhost $port > /dev/null 2>&1
}

##
## Tests;
##   test [--xterm] [--no-stop] test <test-name>  [ovls...] > $log
##   test [--xterm] [--no-stop] > $log   # default test
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
		export __cni
		for t in etcd_vm_reboot master_reboot lb_reboot etcd_k8s_reboot; do
			tlog "=========== $t"
			$me test $t || tdie $t
		done
	fi		

	now=$(date +%s)
	tlog "Xcluster test ended. Total time $((now-begin)) sec"
}
##   test start_empty [--cni=bridge]
##     Start empty cluster
test_start_empty() {
	cd $dir
	test -n "$__nvm" || __nvm=7
	export __image=$XCLUSTER_HOME/hd-k8s-xcluster.img
	test -n "$__nrouters" || export __nrouters=1
	if test -n "$TOPOLOGY"; then
		tlog "Using TOPOLOGY=$TOPOLOGY"
		. $($XCLUSTER ovld network-topology)/$TOPOLOGY/Envsettings
	fi
	export xcluster___cni=$__cni
	xcluster_start network-topology haproxy k8s-cni-$__cni . $@
	$XCLUSTER scaleout $xcluster_ETCD_VMS $xcluster_LB_VMS
	tcase "VM connectivity; $xcluster_ETCD_VMS $xcluster_LB_VMS"
	tex check_vm $xcluster_ETCD_VMS $xcluster_LB_VMS || tdie
}
##   test start
##     Start cluster
test_start() {
	test -n "$__nvm" || __nvm=7
	test_start_empty $@
	test "$xcluster_K8S_DISABLE" = "yes" && return 0

	otc 1 check_namespaces
	otc 1 check_nodes
	otcr vip_routes
	tcase "Taint master nodes [$xcluster_MASTERS]"
	masters="$(echo $xcluster_MASTERS | tr , ' ')"
	kubectl label nodes $masters node-role.kubernetes.io/control-plane=''
	kubectl taint nodes $masters node-role.kubernetes.io/control-plane:NoSchedule
}
##   test start_ha
##     Start a HA K8s cluster using the internal CNI-plugin. This is
##     intended as a template for other ovls testing HA functions
test_start_ha() {
	export __nvm=7
	export xcluster_MASTERS=vm-001,vm-002,vm-003
	export xcluster_ETCD_VMS="193 194 195"
	export xcluster_LB_VMS="191 192"
	unset xcluster_K8S_DISABLE
	xcluster_start network-topology haproxy . $@

	$XCLUSTER scaleout $xcluster_ETCD_VMS $xcluster_LB_VMS
	tcase "VM connectivity; $xcluster_ETCD_VMS $xcluster_LB_VMS"
	tex check_vm $xcluster_ETCD_VMS $xcluster_LB_VMS || tdie

	otc 1 check_namespaces
	otc 1 check_nodes

	tcase "Taint master nodes [$xcluster_MASTERS]"
	masters="$(echo $xcluster_MASTERS | tr , ' ')"
	kubectl label nodes $masters \
		node-role.kubernetes.io/control-plane='' || tdie "label nodes"
	kubectl taint nodes $masters \
		node-role.kubernetes.io/control-plane:NoSchedule || tdie "taint nodes"

	# By default "vip_routes" setup ECMP to all nodes, including
	# control-plane. You might want to change that
	otcr vip_routes
}
##   test etcd_vm_reboot
##     Reboot one etcd VM, restore and reboot ahother. Check health.
##     Influental settings: xcluster_ETCD_VMS, xcluster_ETCD_FAMILY
##     The test is performed without K8s
test_etcd_vm_reboot() {
	test $etcd_size -ge 3 || tdie "Etcd cluster too small"
	export __nvm=0
	export __nrouters=0
	export xcluster_K8S_DISABLE=yes
	unset xcluster_LB_VMS
	test_start_empty
	otc 195 "etcd_health $etcd_size"
	tcase "Stop vm-193"
	cmd_stop_vm 193
	otc 195 "etcd_health $((etcd_size - 1))"
	tcase "Reset and start vm-193"
	cmd_reset_vm 193
	otc 195 "etcd_health $etcd_size"
	tcase "Stop vm-194"
	cmd_stop_vm 194
	otc 195 "etcd_health $((etcd_size - 1))"
	tcase "Reset and start vm-194"
	cmd_reset_vm 194
	otc 195 "etcd_health $etcd_size"
	xcluster_stop
}
##   test etcd_k8s_reboot
##     Reboot the etcd VM one-by-one. Check K8s API server access
test_etcd_k8s_reboot() {
	export xcluster_MASTERS="vm-001,vm-002"
	test -n "$__nvm" || __nvm=4
	test_start
	local vm n
	for n in $xcluster_ETCD_VMS; do
		otc $__nvm check_api
		vm=$(printf "vm-%03d" $n)
		tcase "Stop $vm"
		cmd_stop_vm $n
		otc $__nvm check_api
		tcase "Reset and start $vm"
		cmd_reset_vm $n
		tex check_vm $n || tdie
		otc $n "etcd_health $etcd_size"
	done
	xcluster_stop
}
##   test master_reboot
##     Start with 2 K8s master nodes. Reboot one and test that API
##     access still works. Restore and reboot the other, test again
test_master_reboot() {
	export xcluster_MASTERS="vm-001,vm-002"
	test -n "$__nvm" || __nvm=4
	test_start
	otc 4 check_api
	tcase "Stop vm-001"
	cmd_stop_vm 1
	otc 4 check_api
	tcase "Reset and start vm-001"
	cmd_reset_vm 1
	tcase "Stop vm-002"
	cmd_stop_vm 2
	otc 4 check_api
	tcase "Reset and start vm-002"
	cmd_reset_vm 2
	xcluster_stop
}
##   test lb_reboot
##     Reboot a load-balancer VM, restore, and reboot the other.
##     Check API access
test_lb_reboot() {
	# Check that keepalived is built
	mkdir -p $tmp
	__install=$tmp
	cmd_keepalived || die

	export xcluster_MASTERS="vm-001,vm-002"
	export xcluster_LB_VMS="191 192"
	
	test -n "$__nvm" || __nvm=4
	test_start
	otc 4 check_api
	tcase "Stop vm-191"
	cmd_stop_vm 191
	otc 4 check_api
	tcase "Reset and start vm-191"
	cmd_reset_vm 191
	tcase "Stop vm-192"
	cmd_stop_vm 192
	otc 4 check_api
	tcase "Reset and start vm-192"
	cmd_reset_vm 192
	otc 4 check_api
	xcluster_stop
}


##
test -n "$__nvm" || __nvm=X    # Prevent default setting
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
