#!/bin/sh
set -e
# Keep 'worker' non-privileged on every boot. casper (live session) adds its
# autologin user to admin groups; this strips them back off so worker can never
# install software or escalate. No-op on installed systems where worker is
# already non-admin.
for g in sudo adm docker lxd libvirt lpadmin sambashare; do
  gpasswd -d worker "$g" 2>/dev/null || true
done
# Remove any passwordless-sudo fragment casper may have dropped for the live user.
rm -f /etc/sudoers.d/*casper* /etc/sudoers.d/*live* 2>/dev/null || true
exit 0
