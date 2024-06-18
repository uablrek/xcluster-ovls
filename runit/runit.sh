#! /bin/sh
##
## runit.sh --
##
##   Help script for the xcluster ovl/runit.
##
## Commands;
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
findf() {
	f=$ARCHIVE/$1
	test -r $f && return
	f=$HOME/Downloads/$1
	test -r $f
}

##   env
##     Print environment.
cmd_env() {
	test "$envset" = "yes" && return 0
	envset=yes

	test -n "$PREFIX" || PREFIX=fd00:
	export xcluster_PREFIX=$PREFIX

	eset \
		__nrouters=0 \
		__nvm=1 \
		__runitver=runit-2.1.2
	if test "$cmd" = "env"; then
		local xenv="PREFIX"
		set | grep -E "^($opts|xcluster_($xenv))="
		exit 0
	fi

	test -n "$long_opts" && export $long_opts
	test -n "$XCLUSTER" || die 'Not set [$XCLUSTER]'
	test -x "$XCLUSTER" || die "Not executable [$XCLUSTER]"
	eval $($XCLUSTER env)
}
# Set variables unless already defined. Options (starting with "__")
# are collected into $opts
eset() {
	local e k
	for e in $@; do
		k=$(echo $e | cut -d= -f1)
		echo $k | grep -q '^__' && opts="$opts|$k"
		test -n "$(eval echo \$$k)" || eval $e
	done
}
##   ar
##     Get the runit tar, or die trying
cmd_ar() {
	findf $__runitver.tar.gz || die "Not found [$f]"
	echo $f
}
##   build
##     Unpack and build from source
cmd_build() {
	local d=$XCLUSTER_WORKSPACE/$__runitver
	if ! test -d $d; then
		findf $__runitver.tar.gz || die "Not found [$f]"
		tar -C $XCLUSTER_WORKSPACE --strip-components=1 -xf $f || die Unpack
	fi
	cd $d
	./package/compile
}
##   install --dest=
##     Install runit (called from ./tar)
cmd_install() {
	test -n "$__dest" || die 'No --dest'
	test -d "$__dest" || die "Not a directory [$__dest]"
	local d=$XCLUSTER_WORKSPACE/$__runitver/command
	test -x $d/runit || die "Runit not built?"
	mkdir -p $__dest/sbin
	cp -r $d/* $__dest/sbin
	mv $__dest/sbin/runit-init $__dest
}
##   man [page]
##     Display a runit man page
cmd_man() {
	local d=$XCLUSTER_WORKSPACE/$__runitver/man
	if test -n "$1"; then
		test -r $d/$1 || die "Not readable [$d/$1]"
		xterm -bg '#ddd' -fg '#222' -geometry 80x45 -T $1 -e man $d/$@ &
	else
		cd $d
		ls
	fi
}
##   
##
##   test [--xterm] [--no-stop] [opts...] <test-name> [ovls...]
##   test           # default test
##     Exec tests
cmd_test() {
	cd $dir
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
##     Execute the default test-suite. Intended for CI
test_default() {
	$me test start $@ || die "start" 
}
##   test start_empty
##     Start cluster without runit
test_start_empty() {
	export __image=$XCLUSTER_HOME/hd.img
	test -r $__image || die "Not readable [$__image]"
	test -r $__kbin || die "Not readable [$__kbin]"
	unset XOVLS
	xcluster_start $@
}
##   test start
##     Start cluster with runit
test_start() {
	test_start_empty . $@
}

test -z "$__nvm" && __nvm=X
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
	long_opts="$long_opts $o"
	shift
done
unset o v

# Execute command
trap "die Interrupted" INT TERM
cmd_env
cmd_$cmd "$@"
status=$?
rm -rf $tmp
exit $status
