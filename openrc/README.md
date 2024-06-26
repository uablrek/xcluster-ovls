# Xcluster/ovl - openrc

The [OpenRC](https://github.com/OpenRC/openrc) init system in `xcluster`

This ovl should be included when `openrc` is expected by some other
program (like [k0s](../k0s/README.md)). It installs `openrc` and start
at "default" runlevel with a faked "network" service.

```
# cat /etc/init.d/99openrc.rc 
#! /bin/sh
rc-update add network default
openrc default
```

Check status with:
```
rc-status --servicelist
```

## Build

Build manually:
```
#apt install libpam0g-dev
meson setup -Dpam=false build
meson configure build
cd build
ninja -t list
ninja -t targets
ninja
DESTDIR=/tmp/openrc ninja install
```

