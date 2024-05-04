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
	test -n "$__nrouters" || __nrouters=1
	test -n "$__nvm" || __nvm=4
	if test "$cmd" = "env"; then
		opt="haproxy.+|nvm|nrouters"
		set | grep -E "^(__($opt))="
		exit 0
	fi

	test -n "$XCLUSTER" || die 'Not set [$XCLUSTER]'
	test -x "$XCLUSTER" || die "Not executable [$XCLUSTER]"
	eval $($XCLUSTER env)
}
##   clone [--haproxyd=] [--haproxyver=]
##     Clone the haproxy repo. --depth 1 is used
cmd_clone() {
	test -e "$__haproxyd" && die "Already exist [$__haproxyd]"
	git clone --depth 1 -b $__haproxyver \
		https://github.com/haproxy/haproxy.git $__haproxyd
}
##   build
##     Build HAProxy
cmd_build() {
	test -d "$__haproxyd" || die "Not a directory [$__haproxyd]"
	cd "$__haproxyd"
	make -j$(nproc) TARGET=linux-glibc USE_OPENSSL=1
}
##
##   test [--xterm] [--no-stop] test <test-name> [ovls...] > $log
##   test [--xterm] [--no-stop] > $log   # default test
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
		mkdir -p $(dirname "$__log")
		date > $__log || die "Can't write to log [$__log]"
		test_$t $@ >> $__log
	else
		test_$t $@
	fi

	now=$(date +%s)
	log "Xcluster test ended. Total time $((now-begin)) sec"
}
##   test default
##     Test for CI
test_default() {
	test_sample
}
##   test start_empty
##     Start cluster
test_start_empty() {
	export __image=$XCLUSTER_HOME/hd.img
	unset XOVLS
	export HAPROXY_TEST=yes
	xcluster_start network-topology iptools . $@
	otc 1 version
}
##   test start
##     Start cluster and setup
test_start() {
	__ntesters=1
	test_start_empty $@
	otcr start_haproxy
}
##   test [--count=20] sample
##     Test access an load-balancing
test_sample() {
	test -n "$__count" || __count=20
	test_start $@
	otc 221 "sample --count=$__count"
	xcluster_stop
}


test -n "$__nvm" || __nvm=X    # Prevent default setting
. $($XCLUSTER ovld test)/default/usr/lib/xctest
test "$__nvm" = "X" && unset __nvm
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
cd $dir
cmd_env
cmd_$cmd "$@"
status=$?
rm -rf $tmp
exit $status
