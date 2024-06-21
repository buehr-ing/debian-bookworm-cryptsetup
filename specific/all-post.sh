#!/usr/bin/echo Usage: source
#
# Tasks for all, but should not be part of the bootstrap script.
#
# => Runs in the chroot almost at the end, just <=
# => before the final cleanup task are running. <=
#

# 20240617 Marcel Buehring <https://marcel.buehr.ing>

# swapfile
fallocate -l 512M /swapfile
chmod -c 600 /swapfile
mkswap /swapfile
echo '/swapfile none swap sw 0 0' \
    |sudo tee -a /etc/fstab

# kernel tuning
cat << __SYSCTL__ \
    |tee -a /etc/sysctl.d/local.conf
vm.swappiness=10
vm.vfs_cache_pressure=50
__SYSCTL__

# It must always stay here!
return 0
