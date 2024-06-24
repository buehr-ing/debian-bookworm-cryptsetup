#!/usr/bin/echo Usage: source
#
# Intel DN2800MT / Intel ATOM N2800 - 2c/4t - 1.86 GHz
#
# => Runs in the chroot almost at the end, just <=
# => before the final cleanup task are running. <=
#

# 20240617 Marcel Buehring <https://marcel.buehr.ing>

# network device fix (ugly diff between buster-rescue and bookworm)
sed -r 's/ eth0( |$)/ eno0\1/' \
    -i /etc/network/interfaces.d/* \
    --debug |grep -A2 ^MATCHED
sed -r '/^IP=/{s/:eth0:/:eno0:/}' \
    -i /etc/initramfs-tools/initramfs.conf \
    --debug |grep -A2 ^MATCHED
update-initramfs -ukall

# /etc/default/grub
patch -tl << '__GRUB__' /etc/default/grub
--- /usr/share/grub/default/grub        2023-10-02 14:11:34.000000000 +0000
+++ /etc/default/grub   2024-06-16 08:29:52.165391171 +0000
@@ -1,3 +1,6 @@
+# This file is based on /usr/share/grub/default/grub, some settings
+# have been changed by OVHcloud.
+
 # If you change this file, run 'update-grub' afterwards to update
 # /boot/grub/grub.cfg.
 # For full documentation of the options in this file, see:
@@ -6,15 +9,16 @@
 GRUB_DEFAULT=0
 GRUB_TIMEOUT=5
 GRUB_DISTRIBUTOR=`lsb_release -i -s 2> /dev/null || echo Debian`
-GRUB_CMDLINE_LINUX_DEFAULT="quiet"
-GRUB_CMDLINE_LINUX=""
+GRUB_CMDLINE_LINUX_DEFAULT=""
+GRUB_CMDLINE_LINUX="nomodeset iommu=pt console=tty0"
+GRUB_GFXPAYLOAD_LINUX="text"
 
 # If your computer has multiple operating systems installed, then you
 # probably want to run os-prober. However, if your computer is a host
 # for guest OSes installed via LVM or raw disk devices, running
 # os-prober can cause damage to those guest OSes as it mounts
 # filesystems to look for things.
-GRUB_DISABLE_OS_PROBER=true
+#GRUB_DISABLE_OS_PROBER=false
 
 # Uncomment to enable BadRAM filtering, modify to suit your needs
 # This works with Linux (no patch required) and with any kernel that obtains
__GRUB__
update-grub

# It must always stay here!
return 0
