#!/bin/bash

#
# debian-bookworm-cryptsetup-bootstrap
#

# Copyright (c) 2024 Marcel Buehring <https://marcel.buehr.ing>

# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

set -euo pipefail
shopt -s inherit_errexit

export \
    ARCH=$(dpkg --print-architecture) \
    LANG=C.UTF-8 \
    TERM=xterm-256color \
    DEBIAN_FRONTEND=noninteractive \
    URL=https://raw.githubusercontent.com/buehr-ing/debian-bookworm-cryptsetup/main

# prerequisites
apt-get -qq update
apt-get -qq upgrade
apt-get -qq install \
    curl \
    patch \
    tzdata \
    arch-test \
    dmidecode \
    debootstrap \
    bind9-dnsutils \
    lvm2 \
    parted \
    dosfstools \
    cryptsetup \
    grub-common

#
# gather infos
#

mapfile -d '' INTRO  << __INTRO__
\e[0;31m
Please be advised\e[0m this process will result in the complete deletion of all
data stored on the target disk. Ensure that you have backed up any important
files before proceeding.
__INTRO__
echo -e "${INTRO}"

# target: disk
RESCUE_DISK=$(set +o pipefail;
    grub-probe -t device /boot 2>/dev/null \
        |sed -r 's|/dev/||;s|[0-9]+$||;s|([0-9])p$|\1|')

# https://www.kernel.org/doc/html/latest/admin-guide/devices.html
lsblk -lI8,9 -o+ROTA,MODEL \
    |awk '{if($1!="'${RESCUE_DISK}'" && $6!~/part|lvm|crypt/)print}'

echo -en '\n\e[0;30mEnter target disk (e.g. sdb, nvme1n1 or empty to cancel):\e[0m '
read TARGET_DISK
[ -n "${TARGET_DISK}" ] \
    || exit 0
TARGET_DISK=$(echo ${TARGET_DISK} \
    |sed -r 's/(.*)/\L\1/;s/[^a-z0-9]//g')
[ -n "$(lsblk -nlI8,9 -oNAME,TYPE \
    |awk '{if($1!="'${RESCUE_DISK}'" && \
           $1=="'${TARGET_DISK}'" && \
           $2!~/part|lvm|crypt/)print}')" ] \
    && echo -e '\e[1;32mOK:\e[0;32m '${TARGET_DISK}'\e[0m' \
    || {
        echo -e '\e[1;31mERROR:\e[0;31m '${TARGET_DISK}' is not a possible target disk!\e[0m'
        exit 1
       }

# target: nvme
[ "${TARGET_DISK::4}" == 'nvme' ] \
    && TARGET_NVME=true \
    || unset TARGET_NVME

# target: erase method
echo -en '\n\e[0;30mShould the target disk be (s)hredded or quickly (w)iped? ['${DEFAULT_ERASE:=shred}']:\e[0m '
read TARGET_ERASE
TARGET_ERASE=$(echo ${TARGET_ERASE:-${DEFAULT_ERASE}} \
    |sed -r 's/(.*)/\L\1/;s/[^sw]//g')
[ -n "${TARGET_ERASE}" ] \
    && echo -e '\e[1;32mOK:\e[0;32m '$(echo ${TARGET_ERASE} |sed 's/s/shred/;s/w/wipe/')'\e[0m' \
    || {
        echo -e '\e[1;31mERROR:\e[0;31m Input is invalid\e[0m'
        exit 1
       }

# target: lvm-group
echo -en '\n\e[0;30mEnter target lvm-group ['${DEFAULT_LVG:=system}']:\e[0m '
read TARGET_LVG
TARGET_LVG=$(echo ${TARGET_LVG:-${DEFAULT_LVG}} \
    |sed -r 's/(.*)/\L\1/;s/[^a-z0-9]/_/g')
[ -n "${TARGET_LVG}" ] \
    && echo -e '\e[1;32mOK:\e[0;32m '${TARGET_LVG}'\e[0m' \
    || {
        echo -e '\e[1;31mERROR:\e[0;31m An empty input is invalid\e[0m'
        exit 1
       }

# target: luks
echo -en '\n\e[0;30mEnter target crypt-device ['${DEFAULT_CRYPT:=${TARGET_LVG}_crypt}']:\e[0m '
read TARGET_CRYPT
TARGET_CRYPT=$(echo ${TARGET_CRYPT:-${DEFAULT_CRYPT}} \
    |sed -r 's/(.*)/\L\1/;s/[^a-z0-9]/_/g')
[ -n "${TARGET_CRYPT}" ] \
    && echo -e '\e[1;32mOK:\e[0;32m '${TARGET_CRYPT}'\e[0m' \
    || {
        echo -e '\e[1;31mERROR:\e[0;31m An empty input is invalid\e[0m'
        exit 1
       }


# target: timezone
DEFAULT_TIMEZONE=$(ip -4 r g 8.8.8.8 |awk '{if($1=="8.8.8.8")print$7}' \
    |xargs -rI%% curl --fail --show-error --location \
        https://ipapi.co/%%/timezone 2>/dev/null ||true)
echo -en '\n\e[0;30mEnter target timezone ['${DEFAULT_TIMEZONE:=Etc/UTC}']:\e[0m '
read TARGET_TIMEZONE
TARGET_TIMEZONE=$(echo ${TARGET_TIMEZONE:-${DEFAULT_TIMEZONE}} \
    |sed -r 's|[^A-Za-z0-9/+]+||g')
[ -e /usr/share/zoneinfo/${TARGET_TIMEZONE:-empty} ] \
    && echo -e '\e[1;32mOK:\e[0;32m '${TARGET_TIMEZONE}'\e[0m' \
    || {
        echo -e "\e[1;31mERROR:\e[0;31m No zoneinfo found for ${TARGET_TIMEZONE:-empty}, Etc/UTC is used\e[0m"
        TARGET_TIMEZONE=Etc/UTC
       }

# target: fqhn
DEFAULT_FQHN=$(ip -4 r g 8.8.8.8 |awk '{if($1=="8.8.8.8")print$7}' \
    |xargs -rI%% dig +short -x %% |sed 's/.$//')
echo -en '\n\e[0;30mEnter target fully-qualified hostname ['${DEFAULT_FQHN:=$(hostname -f)}']:\e[0m '
read TARGET_FQHN
TARGET_FQHN=$(echo ${TARGET_FQHN:-${DEFAULT_FQHN}} \
    |sed -r 's/(.*)/\L\1/;s/[^a-z0-9\.-]//g')
[ -n "${TARGET_FQHN}" ] \
    && echo -e '\e[1;32mOK:\e[0;32m '${TARGET_FQHN}'\e[0m' \
    || {
        echo -e '\e[1;31mERROR:\e[0;31m An empty input is invalid\e[0m'
        exit 1
       }

# target: product-name
DEFAULT_PRODNAME=$(for i in {system,baseboard}-product-name;
    do sudo dmidecode -s ${i} \
        |sed -r '/^\s+$/d;s/[^[:alnum:]]//g;s/(.*)/\L\1/';
    done |head -n1)
echo -en '\n\e[0;30mEnter target system product name ['${DEFAULT_PRODNAME:=unknow}']:\e[0m '
read TARGET_PRODNAME
TARGET_PRODNAME=$(echo ${TARGET_PRODNAME:-${DEFAULT_PRODNAME}} \
    |sed -r 's/[^[:alnum:]]//g;s/(.*)/\L\1/')
[ -n "${TARGET_PRODNAME}" ] \
    && echo -e '\e[1;32mOK:\e[0;32m '${TARGET_PRODNAME}'\e[0m' \
    || {
        echo -e '\e[1;31mERROR:\e[0;31m An empty input is invalid\e[0m'
        exit 1
       }

# target: specific
echo -e '\n\e[0;30mSpecific scripts for the target system:\e[0m '
for i in {all,${TARGET_PRODNAME},${TARGET_FQHN#*.},${TARGET_FQHN}}-{pre,post}.sh
do
    curl --fail --silent --location --head \
         --connect-timeout 3 --max-time 1 \
	 --output /dev/null \
	 ${URL}/specific/${i} \
    && {
        TARGET_SPECIFIC+=(${i})
        echo -e '\e[0;32m'${URL}/specific/${i}'\e[0m'
       } \
    || true
done
[ -n "${TARGET_SPECIFIC[*]}" ] \
    || echo -e '\e[1;32mOK:\e[0;32m no specific scripts found\e[0m'

# target: warning
mapfile -d '' WARNING  << __WARNING__
\e[1;31m
WARNING!
========
\e[0;31m
All data on the target disk \e[1;31m${TARGET_DISK}\e[0;31m will be erased!\e[0m
__WARNING__
echo -e "${WARNING}"
echo -en '\e[0;30mAre you sure? (Type \e[1;31myes\e[0;30m in capital letters or empty to cancel):\e[0m '
read ACK
[ "${ACK}" == 'YES' ] \
    && echo -e '\e[1;32mOK:\e[0;32m '${ACK}'\e[0m\n' \
    || exit 0

#
# do the job
#
set -x

# prevent conflicts
umount -v /target/{sys{/firmware/efi/efivars,},proc,dev{/pts,},boot{/efi,},} ||true
vgchange -an ${TARGET_LVG} ||true
cryptsetup close ${TARGET_CRYPT} ||true

# erase
[ "${TARGET_ERASE}" == 's' ] \
    && shred -vn1 /dev/${TARGET_DISK} \
    || wipefs -af /dev/${TARGET_DISK}
parted -s /dev/${TARGET_DISK} mklabel gpt

# bios
parted -sanone /dev/${TARGET_DISK} mkpart bios 2048s 8191s
parted -s /dev/${TARGET_DISK} set 1 bios_grub on

# uefi
parted -sanone /dev/${TARGET_DISK} mkpart uefi fat16 8192s 262143s
parted -s /dev/${TARGET_DISK} set 2 boot on
parted -s /dev/${TARGET_DISK} set 2 esp on
sleep 1s
mkfs.fat -F16 -n EFI /dev/${TARGET_DISK}${TARGET_NVME:+p}2

# boot
parted -saopt /dev/${TARGET_DISK} mkpart boot ext4 134MB  334MB
sleep 1s
mkfs.ext4 -FL boot /dev/${TARGET_DISK}${TARGET_NVME:+p}3

# luks
parted -saopt /dev/${TARGET_DISK} mkpart luks 334MB 100%
sleep 1s
LUKSPASS=$(openssl rand -base64 50 |tr -d '\n')
# 1. default compiled-in (aes-xts-plain64)
# 2. if aes not supported or does not work (serpent-xts-plain64)
[ "$(grep -o '\saes\s' /proc/cpuinfo)" ] \
    && cryptsetup luksFormat \
        /dev/${TARGET_DISK}${TARGET_NVME:+p}4 \
	-qd <(echo -n ${LUKSPASS}) \
    || cryptsetup luksFormat -c serpent-xts-plain64 \
        /dev/${TARGET_DISK}${TARGET_NVME:+p}4 \
	-qd <(echo -n ${LUKSPASS})
cryptsetup open \
    /dev/${TARGET_DISK}${TARGET_NVME:+p}4 \
    ${TARGET_CRYPT} \
    -d <(echo -n ${LUKSPASS})

# lvm2
pvcreate -y /dev/mapper/${TARGET_CRYPT}
vgcreate -y ${TARGET_LVG} /dev/mapper/${TARGET_CRYPT}
lvcreate -yl 100%FREE -n root ${TARGET_LVG}
mkfs.ext4 -L root /dev/mapper/${TARGET_LVG}-root

# debootstrap: target
mkdir -vp /target
mount -v /dev/mapper/${TARGET_LVG}-root /target
mkdir -vp /target/{boot,usr,tmp,var,home,local}
mount -v /dev/${TARGET_DISK}${TARGET_NVME:+p}3 /target/boot
mkdir -vp /target/boot/efi
mount -v /dev/${TARGET_DISK}${TARGET_NVME:+p}2 /target/boot/efi

# debootstrap: detect machine/vm
VIRT=$(set +o pipefail;
    systemd-detect-virt --vm \
        |sed -r 's/(.*)/\U\1/')

# debootstrap: additionals
INCLUDE_NONE=(
    linux-image-${ARCH} grub-efi-${ARCH}{,-signed} zstd
    $(arch-test i386 &>/dev/null && echo grub-pc-bin)
)
INCLUDE_QEMU=(
    linux-image-cloud-${ARCH} grub-cloud-${ARCH} qemu-guest-agent zstd
)
INCLUDE_KVM=(${INCLUDE_QEMU[*]})

INCLUDE=(
    cryptsetup cryptsetup-initramfs dropbear-initramfs keyutils lvm2
    console-setup locales bash-completion sudo vim ssh mosh tmux curl
    fail2ban python3-systemd fasttrack-archive-keyring unattended-upgrades
    arch-test ca-certificates patch
)
eval INCLUDE+=(\${INCLUDE_${VIRT}[*]})

# debootstrap: does it
debootstrap \
    --arch=${ARCH} \
    --components=main,non-free,non-free-firmware,contrib \
    --include=$(IFS=,; echo "${INCLUDE[*]}") \
    bookworm /target http://deb.debian.org/debian

# timezone and locales
echo ${TARGET_TIMEZONE} \
    |tee /target/etc/timezone
ln -vfs /usr/share/zoneinfo/${TARGET_TIMEZONE} \
    /target/etc/localtime
echo LANG=en_US.UTF-8 \
    |tee /target/etc/default/locale
for i in C en_US #de_CH it_CH fr_CH
do
    sed -re 's/^#\s+('${i}'\.UTF-8.*$)/\1/' \
        -i /target/etc/locale.gen \
        --debug |grep -A2 ^MATCHED
done

# network
grep -hv ^# /etc/network/interfaces.d/* \
    |tee /target/etc/network/interfaces.d/50-bootstrap-rescue-init
cp -v /etc/{hosts,resolv.conf} \
    /target/etc/

# hostname
echo ${TARGET_FQHN%%.*} \
    |tee /target/etc/hostname
echo "$(ip -4 r g 8.8.8.8 |awk '{if($1=="8.8.8.8")print$7}') ${TARGET_FQHN} ${TARGET_FQHN%%.*}" \
    |tee -a /target/etc/hosts

# apt: sources
cat << __SOURCES__ \
    |tee /target/etc/apt/sources.list
# Releases of the main packages.
deb http://deb.debian.org/debian bookworm main contrib non-free-firmware non-free
#deb-src http://deb.debian.org/debian bookworm main contrib non-free-firmware non-free

# Updates that cannot wait for the next point release.
deb http://deb.debian.org/debian bookworm-updates main contrib non-free-firmware non-free
#deb-src http://deb.debian.org/debian bookworm-updates main contrib non-free-firmware non-free

# Security releases from the Debian Security Audit Team
deb http://security.debian.org/debian-security bookworm-security main contrib non-free-firmware non-free
#deb-src http://security.debian.org/debian-security bookworm-security main contrib non-free-firmware non-free

# Backports releases.
# stable < stable-backports < stable-backports-staging
deb http://deb.debian.org/debian bookworm-backports main contrib non-free-firmware non-free
#deb-src http://deb.debian.org/debian bookworm-backports main contrib non-free-firmware non-free

# Fast-paced backports releases.
# stable < stable-backports < stable-backports-staging < stable-fasttrack < stable-fasttrack-staging
deb http://fasttrack.debian.net/debian-fasttrack/ bookworm-fasttrack main contrib non-free
#deb-src http://fasttrack.debian.net/debian-fasttrack/ bookworm-fasttrack main contrib non-free
deb http://fasttrack.debian.net/debian-fasttrack/ bookworm-backports-staging main contrib non-free
#deb-src http://fasttrack.debian.net/debian-fasttrack/ bookworm-backports-staging main contrib non-free

# Testing releases of the main packages.
deb http://deb.debian.org/debian testing main contrib non-free-firmware non-free
#deb-src http://deb.debian.org/debian testing main contrib non-free-firmware non-free
__SOURCES__

# apt: keep slim
cat << __APT__ \
    |tee /target/etc/apt/apt.conf.d/02recommends_suggests
APT::Install-Recommends "False";
APT::Install-Suggests   "False";
__APT__

# apt: selection
cat << __SELECTION__ \
    |tee /target/etc/apt/apt.conf.d/04package_selection
DPkg::Post-Invoke { "/usr/bin/dpkg --get-selections >/etc/dpkg/dpkg.sel"; };
RPM::Post-Invoke  { "/usr/bin/dpkg --get-selections >/etc/dpkg/dpkg.sel"; };
__SELECTION__

# apt: pinning
cat << __PREFS__ \
    |tee /target/etc/apt/preferences.d/debian-testing.pref
Package: *
Pin: release o=Debian,a=testing
Pin-Priority: -1

Package: network-manager-openconnect*
#Pin: release o=Debian,a=testing
Pin: version 1.2.10-3
Pin-Priority: 500
__PREFS__

# luks: crypttab
echo "${TARGET_CRYPT} UUID=$(lsblk -noUUID /dev/${TARGET_DISK}${TARGET_NVME:+p}4 |head -n1) none luks,discard,initramfs,keyscript=decrypt_keyctl" \
    |tee /target/etc/crypttab

# luks: initramfs
# a=(ip gw dev mask dns1 dns2 ntp)
a=($(ip -4 r g 8.8.8.8 |awk '{if($1=="8.8.8.8")print$7,$3,$5}'))
a[3]=$(ifconfig ${a[2]} |awk '{if($1=="inet" && $3=="netmask"){print$4;exit}}')
a+=($(awk '{if($1=="nameserver" && $2~/([0-9]+\.)+/)print$2}' /etc/resolv.conf))
a[6]=$(dig +short ntp.metas.ch)
# https://www.metas.ch/metas/en/home/fabe/zeit-und-frequenz/time-dissemination.html
cat << __INITRAMFS__ \
    |tee -a /target/etc/initramfs-tools/initramfs.conf

# ip::gw:mask::dev:off:dns1:dns2:ntp
IP=${a[0]}::${a[1]}:${a[3]}::${a[2]}:off:${a[4]:-1.1.1.1}:${a[5]:-8.8.8.8}:${a[6]:-162.159.200.1}
__INITRAMFS__

# luks: dropbear
cat << __DROPBEAR__ \
    |tee -a /target/etc/dropbear/initramfs/dropbear.conf

DROPBEAR_OPTIONS="-jksc cryptroot-unlock"
__DROPBEAR__
cp -v /root/.ssh/authorized_keys /target/etc/dropbear/initramfs/

# fstab
cat << __FSTAB__ \
    |tee /target/etc/fstab
UUID=$(lsblk -noUUID /dev/${TARGET_DISK}${TARGET_NVME:+p}3 |head -n1) /boot ext4 defaults 0 2
UUID=$(lsblk -noUUID /dev/${TARGET_DISK}${TARGET_NVME:+p}2 |head -n1) /boot/efi vfat defaults 0 2
/dev/mapper/${TARGET_LVG}-root / ext4 relatime 0 1
tmpfs /tmp tmpfs noatime,nosuid 0 0
__FSTAB__

# keyboard
cat << __KEYBOARD__ \
    |tee /target/etc/default/keyboard
XKBLAYOUT="us"
BACKSPACE="guess"
XKBMODEL="pc105"
XKBVARIANT=""
XKBOPTIONS="compose:ralt,terminate:ctrl_alt_bksp"
__KEYBOARD__

# console-setup
cat << __CONSOLE__ \
    |tee /target/etc/default/console-setup
ACTIVE_CONSOLES="/dev/tty[1-6]"
CHARMAP="UTF-8"
CODESET="guess"
FONTFACE="Fixed"
FONTSIZE="8x16"
VIDEOMODE=""
__CONSOLE__

# ssh: sshd_config
sed -r 's/#?(PasswordAuthentication).*/\1 no/' \
    -i /target/etc/ssh/sshd_config
# ssh: authorized_keys
mkdir -vpm 700 /target/root/.ssh
cp -v /root/.ssh/authorized_keys /target/root/.ssh/

# fail2ban: ipv6
cat << __FAIL2BAN__ \
    |tee /target/etc/fail2ban/fail2ban.d/allowipv6_true.conf
[DEFAULT]
allowipv6 = true
__FAIL2BAN__

# fail2ban: jail.d
cat << __JAILD__ \
    |tee /target/etc/fail2ban/jail.d/999-defaults-local.conf
[DEFAULT]
ignoreip = 127.0.0.1/8 ::1/128
backend = systemd
bantime = 600
findtime = 600
maxretry = 5

# fail2ban-client status sshd
# fail2ban-client set sshd unbanip x.x.x.x
[sshd]
enabled = true
__JAILD__

# chroot: devices
mount -vt sysfs none /target/sys
mount -vt efivarfs none /target/sys/firmware/efi/efivars ||true
mount -vt proc none /target/proc
mount -vo bind /dev /target/dev
mount -vo bind /dev/pts /target/dev/pts

# chroot: post-setup
chroot /target /bin/bash << __CHROOT__
shopt -s extglob
set -aeux
source /etc/os-release
set +a
env

# policy-rc: prevent daemons starting
cat << __POLICY_RC__ \
    |tee /usr/sbin/policy-rc.d
#!/bin/sh
exit 101
__POLICY_RC__

# locale
locale-gen
update-locale

# dpkg preseed
cat << __DEBCONF__ \
    |debconf-set-selections -v
#-----------------------------------------------------
tzdata  tzdata/Areas         select ${TARGET_TIMEZONE%/*}
tzdata  tzdata/Zones/Etc     select
tzdata  tzdata/Zones/${TARGET_TIMEZONE%/*}  select ${TARGET_TIMEZONE#*/}
#-----------------------------------------------------
console-setup  console-setup/charmap47  select UTF-8
__DEBCONF__

# apt
apt-get -qq update
apt-get -qq upgrade

# pre-specific
for i in ${TARGET_SPECIFIC[*]/*-post.sh}
do
    source <(curl --fail --silent --location \
        --header 'Cache-Control: no-cache, no-store' \
	--connect-timeout 3 --max-time 30 \
        ${URL}/specific/\${i})
done

# luks: dropbear
for i in ecdsa ed25519 rsa
do
    dropbearconvert \
        openssh dropbear \
        /etc/ssh/ssh_host_\${i}_key \
        /etc/dropbear/initramfs/dropbear_\${i}_host_key
done
update-initramfs -ukall

# grub
# https://manpages.debian.org/unstable/grub2-common/grub-install.8.en.html
cp -v /usr/share/grub/default/grub \
    /etc/default/grub
# grub: bios
arch-test i386 \
    || true \
    && grub-install \
       --target=i386-pc \
       --recheck \
       /dev/${TARGET_DISK}
# grub: efi
amd64=x86_64
aarch64=arm64
grub-install \
    --target=\${!ARCH}-efi \
    --no-nvram \
    --uefi-secure-boot \
    --recheck \
    /dev/${TARGET_DISK}
# grub: test
update-grub

# firewalld
apt-get -qq install firewalld
firewall-offline-cmd --enabled
for i in dhcpv6-client mosh ssh
do 
    firewall-offline-cmd --list-services |grep -q \${i} \
        || firewall-offline-cmd --add-service=\${i}
done
firewall-offline-cmd --list-all

# apt: tasksel
tasksel install \
    standard \
    ssh-server \
    #desktop \
    #gnome-desktop

# post-specific
for i in ${TARGET_SPECIFIC[*]/*-pre.sh}
do
    source <(curl --fail --silent --location \
        --header 'Cache-Control: no-cache, no-store' \
	--connect-timeout 3 --max-time 30 \
        ${URL}/specific/\${i})
done

# apt: cleanup
apt-get -qq autoclean

# policy-rc: re-allows daemons starting
rm -f /usr/sbin/policy-rc.d
__CHROOT__

# unmount
umount -v /target/{sys{/firmware/efi/efivars,},proc,dev{/pts,},boot{/efi,},} ||true
vgchange -an ${TARGET_LVG}
cryptsetup close ${TARGET_CRYPT}

# luks: password
until cryptsetup luksChangeKey /dev/${TARGET_DISK}${TARGET_NVME:+p}4 -d <(echo -n ${LUKSPASS})
do
    echo -e '\e[1;31mERROR:\e[0;31m Failed to set password, please try again..\e[0m'
done

# Success
set +x
echo -e '\e[1;32mSUCCESS:\e[0;32m Please boot the new installed Debian.\e[0m'
