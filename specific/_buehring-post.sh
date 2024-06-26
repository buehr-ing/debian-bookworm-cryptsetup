#!/usr/bin/echo Usage: source
#
# Tasks for buehring only
#
# => Runs in the chroot almost at the end, just <=
# => before the final cleanup task are running. <=
#

# 20240617 Marcel Buehring <https://marcel.buehr.ing>

# /etc/resolv.conf
sed -e '/^domain\s/d;0,/^/i domain buehr.ing' \
    -e '/^search\s/d;0,/^/i search buehr.ing buehring.it buehring.ch buehring.cloud' \
    -i /etc/resolv.conf

# /etc/fail2ban/jail.d/999-defaults-local.conf
a=( 31.10.142.23
    2a02:aa12:c381:4d80::/64
    10.29.0.0/23
    129.132.10.0/25 )
sed -r '0,/^(ignoreip =.*)$/{s//\1 '"${a[*]//\//\\/}"'/}' \
    -i /etc/fail2ban/jail.d/999-defaults-local.conf 

# packages
apt-get install -qq \
    htop \
    psmisc \
    tree \
    git-lfs \
    ncat \
    ethtool \
    net-tools \
    ethstatus \
    strace \
    httpie \
    mlocate \
    apt-file \
    apt-rdepends \
    borgbackup

# It must always stay here!
return 0
