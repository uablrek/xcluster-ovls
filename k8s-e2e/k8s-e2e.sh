#! /bin/sh
##
## k8s-e2e.sh --
##
##   Help script for the xcluster ovl/k8s-e2e.
##
##   Some influential environment variables:
##
##     xcluster_FEATURE_GATES=NFTablesProxyMode=true
##     xcluster_PROXY_MODE=nftables
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
	test -n "$__nvm" || __nvm=4
	test -n "$__nrouters" || __nrouters=0
	test -n "$__e2e" || __e2e=$GOPATH/src/k8s.io/kubernetes/_output/bin/e2e.test
	test -n "$xcluster_DOMAIN" || export xcluster_DOMAIN=cluster.local
	test -n "$xcluster_PREFIX" || export xcluster_PREFIX=fd00:

	if test "$cmd" = "env"; then
		local opt="nvm|nrouters|log|e2e"
		local xenv="DOMAIN|PREFIX"
		set | grep -E "^(__($opt)|xcluster_($xenv))="
		exit 0
	fi

	test -n "$XCLUSTER" || die 'Not set [$XCLUSTER]'
	test -x "$XCLUSTER" || die "Not executable [$XCLUSTER]"
	eval $($XCLUSTER env)
}
##   e2e_list_images
##     List images used for K8s e2e testing
cmd_e2e_list_images() {
	test -x "$__e2e" || die "Not executable [$__e2e]"
	if test "$__all" = "yes"; then
		$__e2e --list-images
		return
	fi
	$__e2e --list-images | grep -E \
		'images/(agnhost|jessie-dnsutils|regression-issue-74839|busybox|nginx|nonewprivs)'
	$__e2e --list-images | grep -E \
		'/(pause):'
}
##   e2e_cache
##     Load images used for K8s e2e testing to the local registry
cmd_e2e_cache() {
	local images=$($XCLUSTER ovld images)/images.sh
	test -x "$images" || die "Not executable [$images]"
	local i
	for i in $(cmd_e2e_list_images); do
		if $images lreg_isloaded $i; then
			log "Already cached [$i]"
		else
			$images lreg_cache $i || die
		fi
	done
}
##   e2e_list
##     List tests cases that are selected. The cluster must be running
##     even though it's not used.
cmd_e2e_list() {
	__parallel=1
	__repeat=0
	mkdir -p $tmp
	cmd_e2e_run -v --dry-run --no-color > $tmp/out
	grep -B2 '^•' $tmp/out | grep -vE '^(•|k8s.io|-)'
	grep -E '^Ran [0-9]+' $tmp/out
}
##   e2e_run [--parallel=20] [--repeat=0] [-- ginkgo_args...]
##     Run the K8s e2e tests. Set $FOCUS and $SKIP to select tests.
cmd_e2e_run() {
	test -x "$__e2e" || die "Not executable [$__e2e]"
	test -n "$__repeat" || __repeat=0
	test -n "$__parallel" || __parallel=20
	test -n "$FOCUS" || export FOCUS='\[sig-network\].*ervice.*\[[Cc]onformance\].*'
	test -n "$SKIP" || SKIP='Disruptive|ESIPP|DNS|GCE|finalizer|ServiceCIDRs'
	export ACK_GINKGO_DEPRECATIONS=2.1.4
	export KUBERNETES_CONFORMANCE_TEST='y'
	# setting these is required to make RuntimeClass tests work ... :/
	export KUBE_CONTAINER_RUNTIME=remote
	export KUBE_CONTAINER_RUNTIME_ENDPOINT=unix:///var/run/crio/crio.sock
	export KUBE_CONTAINER_RUNTIME_NAME=crio
	cd $GOPATH/src/k8s.io/kubernetes || die "cd to K8s dir"
	log "FOCUS [$FOCUS]"
	log "SKIP  [$SKIP]"
	ginkgo --nodes=$__parallel $@ \
		--focus="$FOCUS" \
		--skip="$SKIP" \
		--repeat=$__repeat \
		$__e2e \
		-- \
		--provider=skeleton \
		--dump-logs-on-failure=false \
		--report-dir=/tmp/$USER/e2e-report	\
		--disable-log-dump=true \
		--num-nodes=$__nvm
}

##
##   test [--log=]   # Execute default tests
##   test [--log=] [--xterm] [--no-stop] <test-suite> [ovls...] > logfile
##     Exec tests
cmd_test() {
	start=starts
	test "$__xterm" = "yes" && start=start
	rm -f $XCLUSTER_TMP/cdrom.iso

	local t=default
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
##   test [--wait] start_empty
##     Start empty cluster
test_start_empty() {
	cd $dir
	if test -n "$TOPOLOGY"; then
		tlog "Using TOPOLOGY=$TOPOLOGY"
		. $($XCLUSTER ovld network-topology)/$TOPOLOGY/Envsettings
	fi
	xcluster_start network-topology . $@
	otc 1 check_namespaces
	otc 1 check_nodes
	otcr vip_routes
	test "$__wait" = "yes" && otc 1 wait
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
cmd_$cmd "$@"
status=$?
rm -rf $tmp
exit $status
