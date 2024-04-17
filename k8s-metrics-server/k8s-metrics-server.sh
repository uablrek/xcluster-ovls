#! /bin/sh
##
## k8s-metrics-server.sh --
##
##   Help script for the xcluster ovl/k8s-metrics-server.
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
	test "$envset" = "yes" && return 0
	envset=yes
	test -n "$__nvm" || __nvm=4
	test -n "$__nrouters" || __nrouters=1
	test -n "$__replicas" || __replicas=4
	test -n "$xcluster_DOMAIN" || xcluster_DOMAIN=xcluster
	test -n "$xcluster_PREFIX" || export xcluster_PREFIX=fd00:

	if test "$cmd" = "env"; then
		local opt="nvm|nrouters|ntesters|replicas|log"
		local xenv="DOMAIN|PREFIX"
		set | grep -E "^(__($opt)|xcluster_($xenv))="
		exit 0
	fi

	test -n "$XCLUSTER" || die 'Not set [$XCLUSTER]'
	test -x "$XCLUSTER" || die "Not executable [$XCLUSTER]"
	eval $($XCLUSTER env)
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
	export MSERVER_TEST=yes

	local t=default
	if test -n "$1"; then
		local t=$1
		shift
	fi		

	if test -n "$__log"; then
		mkdir -p $(dirname "$__log")
		date > $__log || die "Can't write to log [$__log]"
		test_$t $@ >> $__log
	else
		test_$t $@
	fi

	now=$(date +%s)
	log "Xcluster test ended. Total time $((now-begin)) sec"
}
##   test start_empty [--wait]
##     Start empty cluster
test_start_empty() {
	cd $dir
	export xcluster_PREFIX=$PREFIX
	export xcluster_API_FLAGS="--runtime-config=api/all=true"
	xcluster_start . $@
	otc 1 check_namespaces
	otc 1 check_nodes
	test "$__wait" = "yes" && otc 1 wait
	otc 1 metrics_server
}
##   test start
##     Start cluster with ovl functions
test_start() {
	test_start_empty k8s-test $@
	otcprog=k8s-test_test
	otcr vip_routes
	otc 1 "svc tserver 10.0.0.0"
	otc 1 "deployment --replicas=$__replicas tserver"
}
##   test default
##     Just test that the metrics-server starts
test_default() {
	test_start_empty
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
cd $dir
cmd_env
cmd_$cmd "$@"
status=$?
rm -rf $tmp
exit $status
