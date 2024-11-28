#! /bin/sh
##
## admin.sh --
##
##   Help script for the xcluster ovl/kquic.
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
	f=$HOME/Downloads/$1
	test -r $f && return 0
	test -n "$ARCHIVE" && f=$ARCHIVE/$1
	test -r $f
}

##   env
##     Print environment.
cmd_env() {
	test "$envset" = "yes" && return 0
	envset=yes

	eset \
		PREFIX=fd00: \
		__nvm=2 \
		__nrouters=0 \
		KQUIC=$GOPATH/src/github.com/lxin/quic \
		__tdir=/tmp/tmp/$USER
	# (I have a tmpfs on /tmp/tmp, while /tmp is not)
	export xcluster_PREFIX=$PREFIX

	if test "$cmd" = "env"; then
		set | grep -E "^($opts)="
		exit 0
	fi

	test -n "$long_opts" && export $long_opts
	test -n "$XCLUSTER" || die 'Not set [$XCLUSTER]'
	test -x "$XCLUSTER" || die "Not executable [$XCLUSTER]"
	eval $($XCLUSTER env)
	otcprog=x-quic_test
}
# Set variables unless already defined
eset() {
	local e k
	for e in $@; do
		k=$(echo $e | cut -d= -f1)
		opts="$opts|$k"
		test -n "$(eval echo \$$k)" || eval $e
		test "$(eval echo \$$k)" = "?" && eval $e
	done
}
##   install <dir>
##     Install files. Called from "./tar"
cmd_install() {
	test -n "$1" || die "No dir"
	test -d $1 || die "Not a directory [$1]"
	local f d
	if test "$__no_module" = "yes"; then
		log "Out-of-tree module NOT installed"
	else
		f=$KQUIC/modules/net/quic/quic.ko
		test -f $f || die "Not a file [$f]"
		d=$1/lib/modules/$(echo $__kver | cut -c7-)/kernel/net/quic
		mkdir -p $d
		cp $f $d
	fi
	f=$KQUIC/libquic/.libs/libquic.so.1
	test -r $f || die "Not readable [$f]"
	d=$1/lib64
	mkdir -p $d
	cp $f $d
	d=$1/bin
	mkdir -p $d
	cp $KQUIC/tests/.libs/*_test $d
	d=$1/root/keys
	mkdir -p $d
	cd $d
	$KQUIC//tests/keys/ca_cert_pkey_psk.sh > /dev/null 2>&1 || die Keys
	cd $dir
}
##   kquic_build [--clean]
##     Build kernel QUIC
cmd_kquic_build() {
	test -d $KQUIC || die "Not a directory [$KQUIC]"
	cd $KQUIC
	test "$__clean" = "yes" && git clean -dxf > /dev/null
	test -f ./configure || ./autogen.sh || die autogen
	test -f Makefile || ./configure || die configure
	make -j$(nproc) || die make
	cd modules/net/quic
	git clean -dxf . > /dev/null
	#CONFIG_IP_QUIC_TEST=m CONFIG_KUNIT=1 CONFIG_NET_HANDSHAKE=1 \
	CONFIG_IP_QUIC=m ROOTDIR=$KQUIC/modules \
		make -j$(nproc) -C $__kobj M=$PWD || die "make modules"
}
##   kernel_build [--menuconfig] [--tdir=]
##     Modify the kernel source to add the "quic" module
cmd_kernel_build() {
	export KERNELDIR=$__tdir/linux
	local ksrc=$KERNELDIR/$__kver
	if ! test -d $ksrc; then
		findf $__kver.tar.xz || dir "$__kver.tar.xz not found"
		mkdir -p $KERNELDIR
		tar -C $KERNELDIR -xf $f
	fi
	if ! test -d $ksrc/net/quic; then
		cp -r $KQUIC/modules/include $KQUIC/modules/net $ksrc
		cd $ksrc
		sed -i 's@.*sctp.*@&\nobj-$(CONFIG_IP_QUIC)\t\t+= quic/@' net/Makefile
		sed -i 's@.*sctp.*@&\nsource "net/quic/Kconfig"@' net/Kconfig
	fi
	$XCLUSTER kernel_build --kobj=$KERNELDIR/obj \
		--kcfg=$dir/config/$__kver --kbin=$KERNELDIR/bzImage \
		|| die kernel_build
	log "Start with: --kbin=$KERNELDIR/bzImage --no_module"
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
	$me test sample $@ || die "sample"
	$me test func $@ || die "func"
	$me test alpn $@ || die "alpn"
	$me test ticket $@ || die "ticket"
}
##   test start_empty
##     Start cluster
test_start_empty() {
	export __image=$XCLUSTER_HOME/hd.img
	test -r $__image || die "Not readable [$__image]"
	test -r $__kbin || die "Not readable [$__kbin]"
	echo "$XOVLS" | grep -q private-reg && unset XOVLS
	test -n "$TOPOLOGY" && \
		. $($XCLUSTER ovld network-topology)/$TOPOLOGY/Envsettings
	xcluster_start network-topology iptools . $@
	otc 1 version
}
##   test start
##     Start cluster and setup
test_start() {
	test_start_empty $@
}
##   test sample
##     Run the "sample_test"
test_sample() {
	test_start $@
	# IPv4
	otc 1 "start_server --port=7770 sample_test"
	otc 1 "check_server sample_test"
	otc 2 "run_client --addr=192.168.1.1 --port=7770 sample_test none none"
	otc 1 "check_server --stopped sample_test"
	# IPv6
	otc 1 "start_server sample_test"
	otc 1 "check_server sample_test"
	otc 2 "run_client --addr=$PREFIX:192.168.1.1 sample_test none none"
	otc 1 "check_server --stopped sample_test"
	# IPv4 hostname. See "DNS.1 = server.test" in the server cert
	otc 1 "start_server sample_test"
	otc 1 "check_server sample_test"
	otc 2 "run_client --addr=192.168.1.1 sample_test none server.test"
	otc 1 "check_server --stopped sample_test"
	# IPv6 hostname
	otc 1 "start_server sample_test"
	otc 1 "check_server sample_test"
	otc 2 "run_client --addr=$PREFIX:192.168.1.1 sample_test none server.test"
	otc 1 "check_server --stopped sample_test"
	# IPv4 psk
	otc 1 "start_server sample_test keys/server-psk.txt none"
	otc 1 "check_server sample_test"
	otc 2 "run_client --addr=192.168.1.1 sample_test keys/client-psk.txt none"
	otc 1 "check_server --stopped sample_test"
	# IPv6 psk
	otc 1 "start_server sample_test keys/server-psk.txt none"
	otc 1 "check_server sample_test"
	otc 2 "run_client --addr=$PREFIX:192.168.1.1 sample_test keys/client-psk.txt none"
	otc 1 "check_server --stopped sample_test"
	
	xcluster_stop
}
##   test func
##     Run the "func_test"
test_func() {
	test_start $@
	# IPv4
	otc 1 "start_server"
	otc 1 "check_server"
	otc 2 "run_client --addr=192.168.1.1"
	otc 1 "check_server --stopped"
	# IPv6
	otc 1 "start_server"
	otc 1 "check_server"
	otc 2 "run_client --addr=$PREFIX:192.168.1.1"
	otc 1 "check_server --stopped"
	xcluster_stop
}
##   test alpn
##     Run the "alpn_test"
test_alpn() {
	test_start $@
	# IPv4
	otc 1 "start_server alpn_test"
	otc 1 "check_server alpn_test"
	otc 2 "run_client --addr=192.168.1.1 alpn_test"
	otc 1 "check_server --stopped alpn_test"
	# IPv6
	otc 1 "start_server alpn_test"
	otc 1 "check_server alpn_test"
	otc 2 "run_client --addr=$PREFIX:192.168.1.1 alpn_test"
	otc 1 "check_server --stopped alpn_test"
	xcluster_stop	
}
##   test ticket
##     Run the "ticket_test"
test_ticket() {
	test_start $@
	# IPv4
	otc 1 "start_server ticket_test"
	otc 1 "check_server ticket_test"
	otc 2 "run_client --addr=192.168.1.1 ticket_test"
	otc 1 "check_server --stopped ticket_test"
	# IPv6
	otc 1 "start_server ticket_test"
	otc 1 "check_server ticket_test"
	otc 2 "run_client --addr=$PREFIX:192.168.1.1 ticket_test"
	otc 1 "check_server --stopped ticket_test"
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
