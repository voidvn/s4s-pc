#!/bin/bash
set -e

# ============================================================================
# First-boot preparation for Vaultwarden. Run by vaultwarden.service before
# `docker compose up`.
#   1. In a LIVE session the root fs is an overlayfs; Docker's overlay2 driver
#      cannot stack on overlayfs, so switch Docker to the vfs driver for the
#      session. (On an INSTALLED system the root is ext4 -> overlay2 default is
#      kept, which is far more space-efficient.)
#   2. Add the desktop user to the docker group (convenience).
#   3. Load the offline-bundled Vaultwarden image if present and not yet loaded.
# ============================================================================

is_live() {
  grep -qa 'boot=casper' /proc/cmdline 2>/dev/null && return 0
  [ -d /run/live ] && return 0
  [ "$(stat -f -c %T / 2>/dev/null)" = "overlayfs" ] && return 0
  return 1
}

if is_live; then
  mkdir -p /etc/docker
  if ! grep -qs '"storage-driver"' /etc/docker/daemon.json; then
    echo '{ "storage-driver": "vfs" }' > /etc/docker/daemon.json
    systemctl restart docker || true
    # give the daemon a moment to come back up
    for _ in $(seq 1 30); do docker info >/dev/null 2>&1 && break; sleep 1; done
  fi
fi

# Convenience: let the live/desktop user run docker without sudo.
getent passwd ubuntu >/dev/null 2>&1 && usermod -aG docker ubuntu || true

# Load the offline image bundle on first boot (offline mode).
if ! docker image inspect vaultwarden/server:latest >/dev/null 2>&1; then
  if [ -f /opt/vaultwarden/vaultwarden.tar ]; then
    echo "vaultwarden-load: loading bundled image…"
    docker load -i /opt/vaultwarden/vaultwarden.tar || true
  fi
fi

exit 0
