#! /bin/sh
##
## haproxy.sh --
##
##   Help script for the xcluster ovl/haproxy.
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
	echo "$prg: $*" >&2
}
dbg() {
	test -n "$__verbose" && echo "$prg: $*" >&2
}

##   env
##     Print environment.
cmd_env() {
	test -n "$__haproxyd" || __haproxyd=$GOPATH/src/github.com/haproxy/haproxy
	test -n "$__haproxyver" || __haproxyver=v2.8.0
	if test "$cmd" = "env"; then
		opt="haproxy.+"
		set | grep -E "^(__($opt))="
		return 0
	fi

	test -n "$XCLUSTER" || die 'Not set [$XCLUSTER]'
	test -x "$XCLUSTER" || die "Not executable [$XCLUSTER]"
	eval $($XCLUSTER env)
}
##   clone [--haproxyd=] [--haproxyver=]
##     Clone the haproxy repo. --depth 1 is used
cmd_clone() {
	cmd_env
	test -e "$__haproxyd" && die "Already exist [$__haproxyd]"
	git clone --depth 1 -b $__haproxyver \
		https://github.com/haproxy/haproxy.git $__haproxyd
}
##   build
##     Build HAProxy
cmd_build() {
	cmd_env
	test -d "$__haproxyd" || die "Not a directory [$__haproxyd]"
	cd "$__haproxyd"
	make -j$(nproc) TARGET=linux-glibc USE_OPENSSL=1
}
##
##   test [--xterm] [--no-stop] test <test-name> [ovls...] > $log
##   test [--xterm] [--no-stop] > $log   # default test
##     Exec tests
cmd_test() {
	cmd_env
    start=starts
    test "$__xterm" = "yes" && start=start
    rm -f $XCLUSTER_TMP/cdrom.iso

    if test -n "$1"; then
		t=$1
		shift
        test_$t $@
    else
        test_start
    fi      

    now=$(date +%s)
    tlog "Xcluster test ended. Total time $((now-begin)) sec"
}

##   test start_empty
##     Start cluster
test_start_empty() {
	export __image=$XCLUSTER_HOME/hd.img
	echo "$XOVLS" | grep -q private-reg && unset XOVLS
	test -n "$TOPOLOGY" && \
		. $($XCLUSTER ovld network-topology)/$TOPOLOGY/Envsettings
	export HAPROXY_TEST=yes
	xcluster_start network-topology iptools . $@
	otc 1 version
}
##   test start
##     Start cluster and setup
test_start() {
	__ntesters=1
	__nrouters=1
	test_start_empty $@
	otcr start_haproxy
}

. $($XCLUSTER ovld test)/default/usr/lib/xctest
indent=''

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
