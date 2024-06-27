# Xcluster/ovl - openrc

The [OpenRC](https://github.com/OpenRC/openrc) init system in `xcluster`

This ovl should be included when `openrc` is expected by some other
program (like [k0s](../k0s/README.md)). It installs `openrc` and start
at "default" runlevel with a faked "network" service.

Check status with:
```
rc-status --servicelist
```

## OpenRC start

The [recommended](https://wiki.gentoo.org/wiki/OpenRC) `/etc/inittab`
is used:

```
::sysinit:/sbin/openrc sysinit
::wait:/sbin/openrc boot
::wait:/sbin/openrc default
```

The original `xcluster` start is called by the "xcluster-start"
service on `boot` runlevel.


## Build

```
eval $(./openrc.sh env | grep __src)
git clone --depth 1 https://github.com/OpenRC/openrc.git $__src
./openrc.sh build
```

Build manually:
```
#apt install libpam0g-dev
# Clone, and cd to the source dir, then
meson setup -Dpam=false build
meson configure build
cd build
ninja -t list
ninja -t targets
ninja
DESTDIR=/tmp/openrc ninja install
```

