#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive HOME=/root LC_ALL=C

# ============================================================================
# Runs INSIDE the chroot. Builds a hardened, audited Ubuntu 24.04 GNOME live
# system: two users (root + non-admin worker), comprehensive auditing
# (auditd + Zeek + OpenSnitch, ~6-month retention), Vaultwarden, LibreOffice /
# VS Code / GIMP, and the ubiquity installer. Invoked by build-iso.sh.
#
# Passwords come from the environment (defaults are intentionally weak — CHANGE
# THEM): ROOT_PASSWORD, WORKER_PASSWORD.
# ============================================================================
ROOT_PASSWORD="${ROOT_PASSWORD:-root}"
WORKER_PASSWORD="${WORKER_PASSWORD:-worker}"
RUSTDESK_PASSWORD="${RUSTDESK_PASSWORD:-}"   # empty => unattended access NOT pre-set

echo "==> [chroot] base configuration"
printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d   # don't start daemons in chroot
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

echo "==> [chroot] kernel + live session (casper) + hardware firmware/drivers"
apt-get install -y --no-install-recommends \
  linux-generic linux-firmware \
  casper ubuntu-standard \
  discover laptop-detect os-prober \
  network-manager network-manager-gnome \
  iw wireless-regdb wpasupplicant rfkill \
  ethtool wakeonlan \
  sudo curl ca-certificates gnupg zstd jq sqlite3 whois

# linux-modules-extra (many Wi-Fi/extra drivers) is a Recommends of the versioned
# kernel image, dropped by --no-install-recommends. The meta name
# 'linux-modules-extra-generic' does NOT exist; install the versioned package for
# the kernel that just landed (derived from /lib/modules).
KVER="$(ls -1 /lib/modules 2>/dev/null | sort -V | tail -1)"
if [ -n "$KVER" ]; then
  apt-get install -y --no-install-recommends "linux-modules-extra-${KVER}" \
    || echo "WARN: linux-modules-extra-${KVER} not found"
fi

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
apt-get install -y --no-install-recommends docker.io docker-compose-v2 skopeo

echo "==> [chroot] productivity apps: LibreOffice, GIMP, VS Code"
apt-get install -y --no-install-recommends libreoffice gimp
# VS Code is not in Ubuntu repos -> Microsoft apt repo.
install -m0755 -d /etc/apt/keyrings
curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
  | gpg --dearmor -o /etc/apt/keyrings/microsoft.gpg
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
  > /etc/apt/sources.list.d/vscode.list
apt-get update || true
apt-get install -y --no-install-recommends code

echo "==> [chroot] media: VLC (+ eog already installed for photos)"
apt-get install -y --no-install-recommends vlc mpv

echo "==> [chroot] extra browsers (Chrome, Firefox-deb, Opera, Yandex)"
# Each third-party repo/install is best-effort: one failure won't abort the build.
install -m0755 -d /etc/apt/keyrings   # self-contained (don't depend on the VS Code block)
# Google Chrome
curl -fsSL https://dl.google.com/linux/linux_signing_key.pub \
  | gpg --dearmor -o /etc/apt/keyrings/google-chrome.gpg 2>/dev/null || true
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main" \
  > /etc/apt/sources.list.d/google-chrome.list
# Firefox — official Mozilla .deb (NOT the Ubuntu snap), pinned above the snap shim
curl -fsSL https://packages.mozilla.org/apt/repo-signing-key.gpg \
  | gpg --dearmor -o /etc/apt/keyrings/packages.mozilla.org.gpg 2>/dev/null || true
echo "deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.gpg] https://packages.mozilla.org/apt mozilla main" \
  > /etc/apt/sources.list.d/mozilla.list
printf 'Package: *\nPin: origin packages.mozilla.org\nPin-Priority: 1000\n' \
  > /etc/apt/preferences.d/mozilla
# Opera
curl -fsSL https://deb.opera.com/archive.key \
  | gpg --dearmor -o /etc/apt/keyrings/opera.gpg 2>/dev/null || true
echo "deb [signed-by=/etc/apt/keyrings/opera.gpg] https://deb.opera.com/opera-stable/ stable non-free" \
  > /etc/apt/sources.list.d/opera.list
echo "opera-stable opera-stable/add-deb-source boolean false" | debconf-set-selections
# Yandex Browser
curl -fsSL https://repo.yandex.ru/yandex-browser/YANDEX-BROWSER-KEY.GPG \
  | gpg --dearmor -o /etc/apt/keyrings/yandex.gpg 2>/dev/null || true
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/yandex.gpg] https://repo.yandex.ru/yandex-browser/deb stable main" \
  > /etc/apt/sources.list.d/yandex-browser.list

apt-get update || true
for pkg in google-chrome-stable firefox opera-stable yandex-browser-stable; do
  apt-get install -y --no-install-recommends "$pkg" || echo "WARN: $pkg failed (repo down?)"
done

echo "==> [chroot] Node.js (LTS) + Claude Code CLI"
curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - || echo "WARN: nodesource setup failed"
apt-get install -y nodejs || echo "WARN: nodejs failed"
# NodeSource nodejs bundles npm; if that path failed, fall back to Ubuntu's npm.
command -v npm >/dev/null 2>&1 || apt-get install -y npm || echo "WARN: npm missing"
# Claude Code CLI — installed only; NO login/credentials baked into the image.
npm install -g @anthropic-ai/claude-code || echo "WARN: claude-code install failed"

echo "==> [chroot] Postman (vendor tarball)"
if curl -fsSL https://dl.pstmn.io/download/latest/linux_64 -o /tmp/postman.tar.gz \
   && tar -xzf /tmp/postman.tar.gz -C /opt; then
  ln -sf /opt/Postman/Postman /usr/local/bin/postman
  cat > /usr/share/applications/postman.desktop <<'PD'
[Desktop Entry]
Type=Application
Name=Postman
Exec=/opt/Postman/Postman
Icon=/opt/Postman/app/resources/app/assets/icon.png
Terminal=false
Categories=Development;
PD
  rm -f /tmp/postman.tar.gz
else
  echo "WARN: Postman download failed"
fi

echo "==> [chroot] RustDesk (remote desktop) + force X11 (Wayland breaks unattended)"
# RustDesk unattended capture/input does NOT work under Wayland (connects but black
# screen + dead input: 'unsupported display server type wayland'). Force Xorg in GDM.
if grep -q 'WaylandEnable' /etc/gdm3/custom.conf; then
  sed -i 's/^#\?\s*WaylandEnable=.*/WaylandEnable=false/' /etc/gdm3/custom.conf
else
  sed -i '/^\[daemon\]/a WaylandEnable=false' /etc/gdm3/custom.conf
fi
# Fetch the latest stable RustDesk .deb (Flutter build, NOT -sciter) from GitHub.
RD_URL="$(curl -fsSL https://api.github.com/repos/rustdesk/rustdesk/releases/latest \
  | jq -r '.assets[] | select(.name|test("x86_64\\.deb$")) | select(.name|test("sciter")|not) | .browser_download_url' | head -n1)"
if [ -n "${RD_URL:-}" ] && curl -fSL -o /tmp/rustdesk.deb "$RD_URL"; then
  apt-get install -y /tmp/rustdesk.deb || echo "WARN: rustdesk install failed"
  # The .deb postinst installs/enables the unit ONLY when PID 1 is systemd (false in
  # a chroot), so install the bundled unit ourselves; enabling is done in the loop below.
  if [ -f /usr/share/rustdesk/files/systemd/rustdesk.service ]; then
    install -Dm644 /usr/share/rustdesk/files/systemd/rustdesk.service \
      /usr/lib/systemd/system/rustdesk.service
  fi
  rm -f /tmp/rustdesk.deb
else
  echo "WARN: could not fetch RustDesk .deb"
fi
# Bake the unattended (INCOMING) password only if provided at build time. Empty =>
# unattended access not pre-configured (avoids shipping a weak shared remote password).
install -d -m700 /etc/rustdesk
printf '%s' "${RUSTDESK_PASSWORD}" > /etc/rustdesk/password
chmod 600 /etc/rustdesk/password
# Never ship a build-host RustDesk config — the ID must be generated per machine.
rm -rf /root/.config/rustdesk

echo "==> [chroot] auditing: auditd + audispd-plugins"
apt-get install -y --no-install-recommends auditd audispd-plugins
# Persistent journald (the drop-in is shipped via overlay; ensure dir exists).
mkdir -p /var/log/journal
systemd-tmpfiles --create --prefix /var/log/journal 2>/dev/null || true

echo "==> [chroot] network logging: OpenSnitch (noble universe) + Zeek (OBS repo)"
apt-get install -y --no-install-recommends opensnitch python3-opensnitch-ui
mkdir -p /var/lib/opensnitchd
# Zeek is NOT in noble -> openSUSE OBS security:zeek repo.
curl -fsSL https://download.opensuse.org/repositories/security:zeek/xUbuntu_24.04/Release.key \
  | gpg --dearmor -o /etc/apt/keyrings/zeek.gpg
echo "deb [signed-by=/etc/apt/keyrings/zeek.gpg] https://download.opensuse.org/repositories/security:/zeek/xUbuntu_24.04/ /" \
  > /etc/apt/sources.list.d/zeek.list
apt-get update || true
apt-get install -y --no-install-recommends zeek-lts
# Configure Zeek: standalone capture on the primary NIC (resolved at boot),
# hourly rotation, ~26-week (182 day) retention.
ZEEKETC=/opt/zeek/etc
cat > "${ZEEKETC}/node.cfg" <<'EOF'
[zeek]
type=standalone
host=localhost
# __IFACE__ is replaced at boot by zeek.service (the live NIC name varies).
interface=af_packet::__IFACE__
EOF
sed -i '/^LogRotationInterval/d; /^LogExpireInterval/d; /^CompressLogs/d' "${ZEEKETC}/zeekctl.cfg"
cat >> "${ZEEKETC}/zeekctl.cfg" <<'EOF'
LogRotationInterval = 3600
LogExpireInterval = 182 day
CompressLogs = 1
EOF

echo "==> [chroot] users: root + non-admin worker"
# root: set a password (unlocks root for console/su; GDM still blocks root GUI login).
echo "root:${ROOT_PASSWORD}" | chpasswd
# worker: normal desktop groups only — NOT sudo, NOT docker, NOT lxd/lpadmin.
useradd -m -s /bin/bash -c "Worker" worker
echo "worker:${WORKER_PASSWORD}" | chpasswd
for g in audio video plugdev netdev bluetooth; do
  getent group "$g" >/dev/null 2>&1 && gpasswd -a worker "$g" >/dev/null || true
done
# Belt-and-suspenders: make sure worker is in none of the admin groups.
for g in sudo adm docker lxd libvirt lpadmin sambashare; do
  gpasswd -d worker "$g" 2>/dev/null || true
done

echo "==> [chroot] audit rules permissions"
chmod 0640 /etc/audit/rules.d/*.rules 2>/dev/null || true
chmod 0644 /etc/polkit-1/rules.d/00-restrict-software-install.rules 2>/dev/null || true

echo "==> [chroot] enable services"
systemctl set-default graphical.target
for u in gdm3 NetworkManager docker auditd opensnitch \
         zeek.service zeek-cron.timer opensnitch-prune.timer \
         vaultwarden.service s4s-lock-worker.service \
         rustdesk.service rustdesk-firstboot.service wake-on-lan.service; do
  systemctl enable "$u" 2>/dev/null || echo "  (enable $u deferred to first boot)"
done

echo "==> [chroot] pin apps to the GNOME dash + compile schemas"
glib-compile-schemas /usr/share/glib-2.0/schemas || true

echo "==> [chroot] regenerate initramfs with casper hooks"
update-initramfs -u

echo "==> [chroot] cleanup"
apt-get autoremove -y
apt-get clean
rm -rf /tmp/* /var/tmp/* /var/lib/apt/lists/*
rm -f /usr/sbin/policy-rc.d
: > /etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -s /etc/machine-id /var/lib/dbus/machine-id
echo "==> [chroot] done"
