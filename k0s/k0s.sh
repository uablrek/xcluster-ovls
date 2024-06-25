#! /bin/sh
##
## k0s.sh --
##
##   Help script for the xcluster ovl/k0s.
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
	eset \
		PREFIX=fd00: \
		__nvm=4 \
		__nrouters=1 \
		__k0sver=v1.30.2+k0s.0 \
		__replicas=4
	export xcluster_PREFIX=$PREFIX
	export xcluster_DOMAIN=cluster.local
	export xcluster_KUBECONFIG=/etc/kubernetes/kubeconfig.k0s
	if test "$cmd" = "env"; then
		local xenv="DOMAIN"
		set | grep -E "^($opts|xcluster_($xenv))="
		exit 0
	fi

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
##   ssh_keys --dest=dir
##     Generate dropbear ssh-keys (called from ./tar)
cmd_ssh_keys() {
	test -n "$__dest" || die "No --dest"
	test -d "$__dest" || die "Not a directory [$__dest]"
	test -r $__dest/id_dropbear && die "Already generated"
	local d=$XCLUSTER_WORKSPACE/dropbear-$__dropbearver
	test -d $d || die "Dropbear not found"
	test -x $d/dropbearkey || die "Not executable [$d/dropbearkey]"
	test -x $d/dropbearconvert || die "Not executable [$d/dropbearconvert]"
	cd $__dest
	$d/dropbearkey -t rsa -f id_dropbear > /dev/null 2>&1 || die dropbearkey
	$d/dropbearconvert dropbear openssh id_dropbear id_dropbear_ssh \
		> /dev/null 2>&1 || die dropbearconvert
}
##   bin [--k0sctl|--airgap]
##     Print the path to the bin, or die trying
cmd_bin() {
	if test "$__k0sctl" = "yes"; then
		findf k0sctl-linux-x64 || die "k0sctl bin not found"
	else
		if test "$__airgap" = "yes"; then
			findf k0s-airgap-bundle-$__k0sver-amd64 \
				|| die "k0s-airgap-bundle bin not found"
		else
			findf k0s-$__k0sver-amd64 || die "k0s bin not found"
		fi
	fi
	test -x $f || chmod a+x $f
	echo $f
}
##   k0sctl_hosts
##     Emit hosts configuration for k0sctl (called from ./tar)
cmd_k0sctl_hosts() {
	cat <<EOF
  hosts:
  - ssh:
      address: 192.168.1.1
      user: root
      port: 22
      keyPath: /root/.ssh/id_dropbear_ssh
    role: controller+worker
    noTaints: true
    os: alpine
    privateInterface: eth1
    privateAddress: 192.168.1.1
    k0sDownloadURL: file:///root/www/k0s-$__k0sver-amd64
EOF
	local n
	for n in $(seq 2 $__nvm); do
		cat <<EOF
  - ssh:
      address: 192.168.1.$n
      user: root
      port: 22
      keyPath: /root/.ssh/id_dropbear_ssh
    role: worker
    os: alpine
    privateInterface: eth1
    privateAddress: 192.168.1.$n
    k0sDownloadURL: file:///root/www/k0s-$__k0sver-amd64
EOF
	done
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
	unset __no_stop
	test -n "$long_opts" && export $long_opts
	$me test single $@ || die "single"
	$me test k0sctl $@ || die "k0sctl"
	$me test tserver $@ || die "tserver"
}
##   test start_empty
##     Start cluster
test_start_empty() {
	export __image=$XCLUSTER_HOME/hd.img
	test -r $__image || die "Not readable [$__image]"
	test -r $__kbin || die "Not readable [$__kbin]"
	unset XOVLS
	export xcluster___k0sver=$__k0sver
	xcluster_start network-topology iptools . $@
	otc 1 version
}
##   test start
##     Start cluster and prepare k0s
test_start() {
	test_start_empty $@
	otcr del_default
	otcwp k0s_prep
}
##   test start_k8s
##     Start cluster prepare k0s, setup private_reg and Calico (dual-stack)
test_start_k8s() {
	export xcluster_CNI_INFO="k0s-calico"
	test_start_empty private-reg $@
	otcr del_default
	otcwp k0s_prep
	otcwp private_reg
	otc 1 "start_k0sctl /root/k0sctl-k0s.yaml"
	otc 1 check_k8s
}
##   test single
##     Airgap install single-node on vm-001
test_single() {
	__nvm=1
	__nrouters=1
	export xcluster_CNI_INFO="k0s-kuberouter"
	test_start $@
	otc 1 start_single
	otc 1 check_k8s
	xcluster_stop
}
##   test k0sctl
##     Airgap install cluster with "k0sctl"
test_k0sctl() {
	__nrouters=1
	export xcluster_CNI_INFO="k0s-kuberouter"
	test_start $@
	otc 1 start_k0sctl
	otc 1 check_k8s
	xcluster_stop
}
##   test [--replicas=4] tserver
##     Perform basic tests with ovl/tserver
test_tserver() {
	test_start_k8s tserver
	otcprog=tserver_test
	otcr vip_routes
	otc 1 "deployment --replicas=$__replicas --nodes=$__nodes tserver"
	otc 1 create_svc
	otc 201 "traffic --replicas=$__replicas 10.0.0.52"
	unset otcprog
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
