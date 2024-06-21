#!/usr/bin/echo Usage: source
#
# Tasks for buehr.ing only
#
# => Runs in the chroot almost at the end, just <=
# => before the final cleanup task are running. <=
#

# 20240617 Marcel Buehring <https://marcel.buehr.ing>

# source buehring-post
source <(curl --fail --silent --location \
    --header 'Cache-Control: no-cache, no-store' \
    --connect-timeout 3 --max-time 30 \
    ${URL}/specific/_buehring-pre.sh)

# It must always stay here!
return 0
