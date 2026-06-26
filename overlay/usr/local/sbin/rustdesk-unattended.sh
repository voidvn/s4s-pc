#!/bin/bash
set -uo pipefail
# First-boot RustDesk provisioning. Runs AS ROOT — the rustdesk systemd service
# runs as root and reads /root/.config/rustdesk/, so the password/options MUST be
# written there (running as the desktop user would write ~/.config and the service
# would ignore it: the classic "permanent password ignored when started as Service").
[ "$(id -u)" -eq 0 ] || exit 0
command -v rustdesk >/dev/null 2>&1 || exit 0

PW="$(cat /etc/rustdesk/password 2>/dev/null || true)"
if [ -z "$PW" ]; then
  echo "rustdesk: no unattended password (set RUSTDESK_PASSWORD at build) — skipping"
  exit 0
fi

# Wait for the service to come up and generate the per-machine device ID.
for _ in $(seq 1 30); do
  [ -n "$(rustdesk --get-id 2>/dev/null || true)" ] && break
  sleep 2
done

# Permanent password for UNATTENDED incoming access (salted hash in RustDesk.toml).
rustdesk --password "$PW" || true
# Authenticate by permanent password only, auto-accept (no manual click popup).
rustdesk --option verification-method use-permanent-password || true
rustdesk --option approve-mode password || true
# Allow signing in at the GDM/lock screen by password — lets you log in remotely
# after a Wake-on-LAN boot, before anyone is physically at the machine.
rustdesk --option allow-logon-screen-password Y || true

systemctl restart rustdesk || true
# Record this machine's dialable ID (read it at the console during setup).
rustdesk --get-id > /var/log/rustdesk-id.txt 2>/dev/null || true
exit 0
