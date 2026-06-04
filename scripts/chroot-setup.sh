#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive HOME=/root LC_ALL=C

# ============================================================================
# Runs INSIDE the chroot. Installs GNOME, Docker, the installer, wires up
# Vaultwarden, and enables the services. Invoked by build-iso.sh.
# ============================================================================

echo "==> [chroot] base configuration"
# Prevent daemons from starting during package installation in the chroot.
printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d
chmod +x /usr/sbin/policy-rc.d

echo "s4s-pc" > /etc/hostname
cat > /etc/hosts <<'EOF'
127.0.0.1   localhost
127.0.1.1   s4s-pc
::1         localhost ip6-localhost ip6-loopback
EOF

apt-get update

echo "==> [chroot] locales"
apt-get install -y --no-install-recommends locales
sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen en_US.UTF-8
update-locale LANG=en_US.UTF-8

echo "==> [chroot] kernel + live session (casper)"
apt-get install -y --no-install-recommends \
  linux-generic \
  casper \
  ubuntu-standard \
  discover laptop-detect os-prober \
  network-manager network-manager-gnome \
  sudo curl ca-certificates gnupg zstd

echo "==> [chroot] GNOME desktop (curated; no snap)"
apt-get install -y --no-install-recommends \
  xorg \
  gnome-session gnome-shell gnome-shell-extension-ubuntu-dock \
  gdm3 gnome-settings-daemon gnome-control-center \
  gnome-terminal nautilus gnome-text-editor \
  xdg-desktop-portal-gnome dbus-user-session polkitd \
  gnome-system-monitor gnome-disk-utility eog \
  epiphany-browser \
  yaru-theme-gtk yaru-theme-icon yaru-theme-sound \
  fonts-ubuntu fonts-dejavu-core \
  language-pack-en language-pack-gnome-en

echo "==> [chroot] Docker + Vaultwarden runtime"
apt-get install -y --no-install-recommends \
  docker.io docker-compose-v2 skopeo

echo "==> [chroot] installer (install-to-disk)"
apt-get install -y --no-install-recommends \
  ubiquity ubiquity-frontend-gtk ubiquity-slideshow-ubuntu \
  || echo "WARN: ubiquity unavailable — image will be live-only"

echo "==> [chroot] enable services"
systemctl set-default graphical.target
systemctl enable gdm3 || true
systemctl enable NetworkManager || true
systemctl enable docker || true
systemctl enable vaultwarden.service || true

# NetworkManager owns networking in the live/desktop session.
chmod 0600 /etc/netplan/01-network-manager-all.yaml 2>/dev/null || true

echo "==> [chroot] pin Vaultwarden + browser to the GNOME dash"
glib-compile-schemas /usr/share/glib-2.0/schemas || true

echo "==> [chroot] regenerate initramfs with casper hooks"
update-initramfs -u

echo "==> [chroot] cleanup"
apt-get autoremove -y
apt-get clean
rm -rf /tmp/* /var/tmp/* /var/lib/apt/lists/*
rm -f /usr/sbin/policy-rc.d
# Fresh machine-id on each boot.
: > /etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -s /etc/machine-id /var/lib/dbus/machine-id

echo "==> [chroot] done"
