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
		test_basic
	fi		

	now=$(date +%s)
	tlog "Xcluster test ended. Total time $((now-begin)) sec"
}
##   test start_empty
##     Start empty cluster
test_start_empty() {
	export xcluster_PREFIX=$PREFIX
	xcluster_start tserver $@
	otc 1 check_namespaces
	otc 1 check_nodes
	otcr vip_routes
}
##   test start
##     Start cluster with ovl functions
test_start() {
	test_start_empty $@
	otc 1 start_tserver
}
##   test connectivity (default)
##     Test external connectivity
test_basic() {
	tlog "=== Test external connectivity"
	test_start $@
	otc 1 create_svc
	otc 201 external_traffic
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
