#!/usr/bin/echo Usage: source
#
# Tasks for sync.buehr.ing only
#
# => Runs in the chroot almost at the end, just <=
# => before the final cleanup task are running. <=
#

# 20240617 Marcel Buehring <https://marcel.buehr.ing>

# data_crypt
echo 'data_crypt UUID=0d15c67a-0eb4-4294-bc0c-40b0d71caca5 none luks,discard,initramfs,keyscript=decrypt_keyctl' \
    |tee -a /etc/crypttab
echo '/dev/mapper/data-local /local ext4 noatime 0 2' \
    |tee -a /etc/fstab

# docker-ce
curl -fsSL https://download.docker.com/linux/debian/gpg \
     -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian ${VERSION_CODENAME} stable" \
    |tee /etc/apt/sources.list.d/docker.list
apt-get -qq update
apt-get -qq install \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin
ln -fs /usr/libexec/docker/cli-plugins/docker-compose \
    /usr/local/bin/docker-compose

# ctop
curl -fsSL https://github.com/bcicen/ctop/releases/download/v0.7.7/ctop-0.7.7-linux-amd64 \
     -o /usr/local/bin/ctop
chmod +x /usr/local/bin/ctop

# containerroot:containerroot (500:500)
groupadd \
    --gid 500 \
    --system containerroot
useradd \
    --uid 500 \
    --gid 500 \
    --home-dir /local/containers \
    --no-create-home \
    --shell /sbin/nologin \
    --comment 'Container Administrator' \
    --system containerroot
mkdir -m 2775 \
    /local/containers
chown containerroot:containerroot \
    /local/containers
ln -fs /local/containers \
    /opt/

# seafile:seafile (8000:8000)
groupadd \
    --gid 8000 \
    --system seafile
useradd \
    --uid 8000 \
    --gid 8000 \
    --home-dir /local/containers/seafile \
    --no-create-home \
    --shell /sbin/nologin \
    --comment 'Seafile Server' \
    seafile
mkdir -m 2770 \
    /local/containers/seafile
chown seafile \
    /local/containers/seafile

# It must always stay here!
return 0
