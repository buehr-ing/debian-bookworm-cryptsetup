# debian-bookworm-cryptsetup-bootstrap
This script automates the fiddling when I want to get a Debian vanilla fully encrypted to the hard disk of a cloud hoster via the rescue console. It requires a Debian-related rescue live system, it does not work with the rescue mode of the Debian installer.

## Usage

First, install the hosted server with the Debian Bookworm template of the hoster and look around. What is the name of the first disk and the first network interface? Are there any special kernel modules and Debian packages from the hoster? How is the boot loader configured, are there any special boot parameters that should be adopted?

If there are host specific settings, customizations or fixes necessary where the script does not cover, you can run additional scripts after the debootstrap. But these host-specific scripts do not replace a configuration management such Ansible or Puppet. These scripts only run once in the chroot after debootstrap and can therefore help to prepare the system for configuration management.

The bootstrap script searches for other scripts in the [specific](specific) folder according to the following patterns and in the order below. `*-pre` runs in the chroot almost at the beginning, just after locale and apt was initialized. And `*-post` runs in the chroot almost at the end, just before the final cleanup task are running.

```bash
all-{pre,post}
${hostdomain}-{pre,post}
${hostname}-{pre,post}
${productname}-{pre,post}
```

Start now the rescue console and copy your ssh-pubkey to `~/.ssh/authorized_keys` of the user `root`, preferably via ssh. You can also use a kvm, but the rescue console is much more convenient and stable to use via ssh. In the rescue console, then run the following command line as `root` to fetch and start the bootstrap script.

```bash
bash <(curl -fsL https://raw.githubusercontent.com/buehr-ing/debian-bookworm-cryptsetup/main/bootstrap.sh) 2>&1 |tee log.txt
```

First, the required packages are installed and then a short dialog starts to collect information for the installation. The default values are usually what is needed and should only be adjusted in special cases. 

To encrypt the hard disk, a random password is generated, which you must change at the end of the execution. After the first dialog until the password is changed, the script runs without any user input unless an error occurs. A log.txt is written to check the progress in the case of an error.

```bash
less -r log.txt
```

## Additonal encrypted disk

Use the same password as with `system_crypt`. 

### New data_crypt

**Please be advised** this process will result in the complete deletion of all data stored on the target disk. Ensure that you have backed up any important files before proceeding.

```bash
disk=sdb

apt-get install -y parted
shred -vn1 /dev/${disk}
parted /dev/${disk} mklabel gpt
parted -aopt /dev/${disk} mkpart luks 0% 100%

cryptsetup luksFormat /dev/${disk}1
echo "data_crypt UUID=$(lsblk -noUUID /dev/sdb1 |head -n1) none luks,discard,initramfs,keyscript=decrypt_keyctl" |tee -a /etc/crypttab

cryptsetup open /dev/${disk}1 data_crypt

pvcreate /dev/mapper/data_crypt
vgcreate data /dev/mapper/data_crypt
lvcreate -l 100%FREE -n local data
mkfs.ext4 -L local /dev/mapper/data-local

echo '/dev/mapper/data-local /local ext4 noatime 0 2' |tee -a /etc/fstab
systemctl daemon-reload
mount -av
```

### Existing data_crypt after OS re-installation

```bash
disk=sdb

echo "data_crypt UUID=$(lsblk -noUUID /dev/${disk}1 |head -n1) none luks,discard,initramfs,keyscript=decrypt_keyctl" |tee -a /etc/crypttab
cryptsetup open /dev/${disk}1 data_crypt

echo '/dev/mapper/data-local /local ext4 noatime 0 2' |tee -a /etc/fstab
systemctl daemon-reload
mount -av
```

## Troubleshooting with rescue console

### mount and chroot

```bash
disk=sda

cryptsetup open /dev/${disk}4 system_crypt
sleep 1s
mkdir -vp /target
mount -v /dev/mapper/system-root /target
mount -v /dev/${disk}3 /target/boot
mount -v /dev/${disk}2 /target/boot/efi
mount -vt sysfs none /target/sys
mount -vt efivarfs none /target/sys/firmware/efi/efivars ||true
mount -vt proc none /target/proc
mount -vo bind /dev /target/dev
mount -vo bind /dev/pts /target/dev/pts
LANG=C.UTF-8 chroot /target /bin/bash
```

### unchroot and unmount 

```bash
# leave chroot with CTRL+D or exit

umount -v /target/{sys{/firmware/efi/efivars,},proc,dev{/pts,},boot{/efi,},} 
vgchange -an system
cryptsetup close system_crypt
```

## Release History
_(Nothing yet)_

## License
MIT
