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

For BusyBox systems it is [recommended](
https://wiki.gentoo.org/wiki/OpenRC) to use a `/etc/inittab` like:

```
::sysinit:/sbin/openrc sysinit
::wait:/sbin/openrc boot
::wait:/sbin/openrc default
```

This is prepared with a "xcluster-start" service on `boot` runlevel
that calls the original `xcluster` start, but for now openrc is
started from an init-script:

```
# cat /etc/init.d/99openrc.rc 
#! /bin/sh
rm -rf /run/openrc    # /run is not a ramdisk (yet...)
openrc default
```


## Build

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

