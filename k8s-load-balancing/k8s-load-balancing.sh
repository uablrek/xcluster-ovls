#! /bin/sh
##
## k8s-load-balancing.sh --
##
##   Help script for the xcluster ovl/k8s-load-balancing.
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

## Commands;
##

##   env
##     Print environment.
cmd_env() {
	test "$envread" = "yes" && return 0
	envread=yes
	test "$__nvm" = "X" && export __nvm=10
	test -n "$__nrouters" || export __nrouters=1
	test -n "$__mode" || __mode=ipvs
	test -n "$__replicas" || __replicas=100
	if test "$cmd" = "env"; then
		opts="mode|replicas|nvm"
		set | grep -E "^(__($opts))="
		return 0
	fi

	test -n "$xcluster_DOMAIN" || xcluster_DOMAIN=xcluster
	test -n "$XCLUSTER" || die 'Not set [$XCLUSTER]'
	test -x "$XCLUSTER" || die "Not executable [$XCLUSTER]"
	eval $($XCLUSTER env)
}
cmd_freq() {
	cmd_env	
	test -n "$1" || return 0
	test -r "$1" || die "Not readable [$1]"
	cat $1 | jq '.hosts|flatten|.[]' | sort | uniq -c | sort -n -k 2
	local cnt=$(cat $1 | jq '.hosts|flatten|.[]' | wc -l)
	if test $cnt -lt $__replicas; then
		log "Only $cnt targets of $__replicas got connections"
		echo "   0 $((__replicas - cnt))"
	fi
}
##   table [mconnect-*]
##     Create a table with frequencies from the passed files. The
##     files must be output from mconnect in json format and have
##     names beginning with "mconnect-", like "/tmp/mconnect-*"
cmd_table() {
	test -n "$1" || return 0
	local m f cnames files
	for f in $@; do
		# Convert to frequencies
		test -r $f || die "Not readable [$f]"
		m=$(basename $f | sed -e 's,mconnect-,,')
		cmd_freq $f | sed -e 's,^   ,,' > /tmp/freq-$m
		files="$files /tmp/freq-$m"
		if test -n "$cnames"; then
			cnames="$cnames,$m"
		else
			cnames=$m
		fi
	done
	paste $files | tr '\t' : | column -t -s: -N $cnames
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
		die "No test specified"
	fi		

	now=$(date +%s)
	tlog "Xcluster test ended. Total time $((now-begin)) sec"
}
##   test start_empty
##     Start empty cluster. Setup source ranges
test_start_empty() {
	cd $dir
	export xcluster_PREFIX=$PREFIX
	xcluster_start network-topology . $@
    otcwp conntrack_size
    local ctsize=$((__replicas * 4000 + 20000))
    otcr "conntrack_size $ctsize"
	otc 1 check_namespaces
	otc 1 check_nodes
	otcr add_address_range
	otcwp client_routes
	otcr vip_routes
}
##   test [--mode=kube-proxy_mode] [--ecmp] start
##     Start cluster with ovl functions
test_start() {
	echo $__mode | grep -qE '^(ipvs|iptables|nftables)$' \
		|| tdie "Invalid mode [$__mode]"
	export xcluster_PROXY_MODE=$__mode
	test "$__mode" = "nftables" && \
		export xcluster_FEATURE_GATES=NFTablesProxyMode=true
	test_start_empty $@
	test "$__ecmp" = "yes" || otcr "vip_routes 192.168.1.2"
	otc 1 "create_1svc tserver 10.0.0.1"
	otc 1 "start_server --replicas=$__replicas"
}
##   test start_cilium [--xmem=1024]
##     Start cluster with ovl functions and the Cilium CNI-plugin
test_start_cilium() {
	export xcluster_PROXY_MODE=disabled
	test -n "$__xmem" || __xmem=1024
	export __mem=$((__mem + __xmem))
	export __mem1=$((__mem1 + __xmem))
	test_start_empty k8s-cni-cilium $@
	test "$__ecmp" = "yes" || otcr "vip_routes 192.168.1.2"
	otc 1 "create_1svc tserver 10.0.0.1"
	otc 1 "start_server --replicas=$__replicas"
}
##   test conntrack_clear
##     Clear conntrack tables in a running cluster
test_conntrack_clear() {
	otcwp conntrack_clear
	otcr conntrack_clear
}
##   test external [--tag=]
##     Test distribution from an external machine, vm-201
test_external() {
	test "$__no_start" = "yes" || test_start $@
	test -n "$__tag" || __tag=$xcluster_PROXY_MODE
	otc 201 "external_access --nconn=$__nconn --ipv6=$__ipv6"
	local out=/tmp/mconnect-$__tag
	rcp 201 /tmp/mconnect $out || tdie "Rcp $out"
	xcluster_stop
	tlog "Frequencies:"
	cmd_freq $out >&2
}
##   test from_pod [--tag=] [--nconn=] 
##     Test distribution from a POD. A rendom tserver POD is used, so
##     hairpin connects must work.
test_from_pod() {
	test -n "$__tag" || __tag=test
	test -n "$__nconn" || __nconn=10000
	local pod=$(kubectl get pods -l app=tserver -o name | shuf | head -1)
	test -n "$pod" || die "Can't find a POD"
	local out=/tmp/mconnect-$__tag
	kubectl exec $pod -- \
		mconnect -address tserver:5001 -nconn=$__nconn -output json $@ > $out
	tlog "Frequencies:"
	cmd_freq $out >&2
}

##   test nodeport [--tag=] [--nconn=] <node-address> [mconnect options...]
##     Test access via a nodePort from the host
test_nodeport() {
	test -n "$1" || die "No node-address"
	local nodeip=$1
	shift
	which mconnect > /dev/null || die "Not executable [mconnect]"
	test -n "$__tag" || __tag=test
	test -n "$__nconn" || __nconn=10000
	local out=/tmp/mconnect-$__tag
	mconnect -address=[$nodeip]:30001 -nconn=$__nconn -output json $@ > $out
	tlog "Frequencies:"
	cmd_freq $out >&2
}

##
__nvm=X
. $($XCLUSTER ovld test)/default/usr/lib/xctest
unset __mode
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
