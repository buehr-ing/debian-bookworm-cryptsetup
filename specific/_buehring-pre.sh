#!/usr/bin/echo Usage: source
#
# Tasks for buehring only
#
# => Runs in the chroot almost at the beginning, <=
# => just after locale and apt was initialized.  <=
#

# 20240617 Marcel Buehring <https://marcel.buehr.ing>

# locales
for i in de_CH it_CH
do
    sed -re 's/^#\s+('${i}'\.UTF-8.*$)/\1/' \
        -i /etc/locale.gen \
        --debug |grep -A2 ^MATCHED
done
locale-gen
update-locale

# It must always stay here!
return 0
