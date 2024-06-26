#! /bin/sh
##
## openrc.sh --
##
##   Help script for the xcluster ovl/openrc.
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

##   env
##     Print environment.
cmd_env() {
	test "$envset" = "yes" && return 0
	envset=yes

	eset \
		PREFIX=fd00: \
		__nvm=1 \
		__nrouters=0 \
		__src=$GOPATH/src/github.com/OpenRC/openrc
	test -n "$PREFIX" || PREFIX=fd00:
	test -n "$__nvm" || __nvm=1
	test -n "$__nrouters" || __nrouters=0
	export xcluster_PREFIX=$PREFIX

	if test "$cmd" = "env"; then
		set | grep -E "^($opt|xcluster_.*)="
		exit 0
	fi

	test -n "$long_opts" && export $long_opts
	test -n "$XCLUSTER" || die 'Not set [$XCLUSTER]'
	test -x "$XCLUSTER" || die "Not executable [$XCLUSTER]"
	eval $($XCLUSTER env)
}
# Set variables unless already defined
eset() {
	local e k
	for e in $@; do
		k=$(echo $e | cut -d= -f1)
		opt="$opt|$k"
		test -n "$(eval echo \$$k)" || eval $e
	done
}
##   man [page]
##     Display an openrc man page
cmd_man() {
	test -d $__src/man || die "Not a directory [$__src/man]"
	cd $__src/man
	if test -n "$1"; then
		test -r ./$1 || die "Not readable [$1]"
		xterm -bg '#ddd' -fg '#222' -geometry 80x43 -T $1 -e man ./$1 &
	else
		ls *.[0-9]
	fi
}
##   build [--force]
##     Build openrc
cmd_build() {
	test -d $__src || die "Source not found"
	test "$__force" = "yes" && rm -rf $__src/build
	if test -d $__src/build; then
		log "Already built"
		return 0
	fi
	cd $__src
	mkdir build
	meson setup -Dpam=false build || die "meson setup"
	cd build
	ninja || die ninja
}
##   install --dest=dir
##     Install a subset of openrc
cmd_install() {
	test -n "$__dest" || die "No --dest"
	test -d "$__dest" || die "Not a directory [$__dest]"
	test -d $__src/build || die "Not built"
	mkdir -p $tmp
	cd $__src/build
	DESTDIR=$tmp ninja install > /dev/null || die "ninja install"
	cp -R $tmp/sbin $tmp/bin $__dest
	mkdir -p $__dest/etc
	cp $tmp/etc/rc.conf $__dest/etc
	mkdir -p $__dest/lib
	cp -R $tmp/lib/rc $__dest/lib
	cp -R $tmp/lib/x86_64-linux-gnu $__dest/lib
}
##
##   test [--xterm] [--no-stop] [opts...] <test-name> [ovls...]
##   test           # default test
##     Exec tests
cmd_test() {
	cd $dir
	start=starts
	test "$__xterm" = "yes" && start=start
	rm -f $XCLUSTER_TMP/cdrom.iso
	export TEST_OPENRC=yes

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
	$me test basic $@ || die "basic" 
}
##   test start_empty
##     Start cluster
test_start_empty() {
	export __image=$XCLUSTER_HOME/hd.img
	test -r $__image || die "Not readable [$__image]"
	test -r $__kbin || die "Not readable [$__kbin]"
	unset XOVLS
	xcluster_start network-topology iptools . $@
	otc 1 version
}
##   test start
##     Start cluster and setup
test_start() {
	test_start_empty $@
}
##   test basic
##     Just start and stop
test_basic() {
	test_start $@
	xcluster_stop
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
