# Xcluster/ovl - runit

The [runit](https://smarden.org/runit/) init system on `xcluster`

This ovl makes `xcluster` start with the `runit` init system. The
"original" start script, `/etc/init.d/rcS`, is called from
"/etc/runit/1".

The `poweroff` and `reboot` BusyBox utilities are replaced by scripts
calling `/runit-init`, and `/etc/inittab` is removed.



