#!/bin/bash
set -euo pipefail

# ============================================================================
# s4s-pc — build a BIOS+UEFI bootable Ubuntu 24.04 (noble) GNOME live ISO from
# scratch with debootstrap, with Vaultwarden (dockerized) preinstalled.
# Runs INSIDE the privileged amd64 builder container.
# ============================================================================

ARCH="${ARCH:-amd64}"
SUITE="${SUITE:-noble}"
MIRROR="${MIRROR:-http://archive.ubuntu.com/ubuntu/}"
SECMIRROR="${SECMIRROR:-http://security.ubuntu.com/ubuntu/}"
VW_MODE="${VW_MODE:-offline}"             # offline = bundle image | pull = fetch on 1st boot
ROOT_PASSWORD="${ROOT_PASSWORD:-root}"    # CHANGE THESE: passwords for the two accounts
WORKER_PASSWORD="${WORKER_PASSWORD:-worker}"
RUSTDESK_PASSWORD="${RUSTDESK_PASSWORD:-}"  # empty => RustDesk unattended access not pre-set
VOLID="S4S_PC"
ISO_NAME="${ISO_NAME:-s4s-pc-${SUITE}-amd64.iso}"

ROOT=/build
WORK="${ROOT}/work"
CHROOT="${WORK}/chroot"
IMG="${WORK}/image"
OUT="${ROOT}/out"

log(){ echo "==> $*"; }

# --- always unmount the chroot binds on exit --------------------------------
cleanup_mounts() {
  for m in dev/pts dev proc sys run; do
    if mountpoint -q "${CHROOT}/${m}" 2>/dev/null; then
      umount -lf "${CHROOT}/${m}" 2>/dev/null || true
    fi
  done
}
trap cleanup_mounts EXIT

rm -rf "${WORK}"
mkdir -p "${CHROOT}" "${IMG}/casper" "${IMG}/boot/grub" "${IMG}/EFI/boot" "${IMG}/.disk" "${OUT}"

# === 1. Bootstrap the base system ==========================================
log "debootstrap ${SUITE} (${ARCH}) — downloads the base system"
debootstrap --arch="${ARCH}" --variant=minbase \
  --components=main,restricted,universe,multiverse \
  "${SUITE}" "${CHROOT}" "${MIRROR}"

# === 2. apt sources inside the chroot ======================================
cat > "${CHROOT}/etc/apt/sources.list" <<EOF
deb ${MIRROR} ${SUITE} main restricted universe multiverse
deb ${MIRROR} ${SUITE}-updates main restricted universe multiverse
deb ${SECMIRROR} ${SUITE}-security main restricted universe multiverse
EOF

# === 3. Bind mounts + DNS ==================================================
cp /etc/resolv.conf "${CHROOT}/etc/resolv.conf"
mount --bind /dev      "${CHROOT}/dev"
mount --bind /dev/pts  "${CHROOT}/dev/pts"
mount -t proc  proc    "${CHROOT}/proc"
mount -t sysfs sysfs   "${CHROOT}/sys"
mount -t tmpfs tmpfs   "${CHROOT}/run"

# === 4. Overlay files (systemd units, compose, launchers, configs) =========
log "copying overlay/ into the rootfs"
cp -a "${ROOT}/overlay/." "${CHROOT}/"
chmod +x "${CHROOT}/usr/local/bin/"*.sh "${CHROOT}/usr/local/sbin/"*.sh 2>/dev/null || true

# === 5. Vaultwarden offline bundle (skopeo -> docker-archive tar) ===========
mkdir -p "${CHROOT}/opt/vaultwarden"
if [ "${VW_MODE}" = "offline" ]; then
  log "bundling vaultwarden/server image offline via skopeo (needs network)"
  skopeo copy --override-os linux --override-arch "${ARCH}" \
    docker://docker.io/vaultwarden/server:latest \
    docker-archive:"${CHROOT}/opt/vaultwarden/vaultwarden.tar":vaultwarden/server:latest
else
  log "VW_MODE=pull — image will be pulled on first boot (needs internet then)"
fi
echo "VW_MODE=${VW_MODE}" > "${CHROOT}/opt/vaultwarden/.vw_mode"

# === 6. Configure the system inside the chroot =============================
cp "${ROOT}/scripts/chroot-setup.sh" "${CHROOT}/root/chroot-setup.sh"
chmod +x "${CHROOT}/root/chroot-setup.sh"
log "running chroot-setup.sh (users, GNOME, Docker, auditing, apps, installer)"
chroot "${CHROOT}" env ROOT_PASSWORD="${ROOT_PASSWORD}" WORKER_PASSWORD="${WORKER_PASSWORD}" \
  RUSTDESK_PASSWORD="${RUSTDESK_PASSWORD}" \
  /root/chroot-setup.sh
rm -f "${CHROOT}/root/chroot-setup.sh"

# === 7. Kernel + initrd + package manifest ================================
log "extracting kernel + initrd"
cp "${CHROOT}"/boot/vmlinuz-*    "${IMG}/casper/vmlinuz"
cp "${CHROOT}"/boot/initrd.img-* "${IMG}/casper/initrd"
chroot "${CHROOT}" dpkg-query -W --showformat='${Package} ${Version}\n' \
  > "${IMG}/casper/filesystem.manifest"
cp "${IMG}/casper/filesystem.manifest" "${IMG}/casper/filesystem.manifest-desktop"

# === 8. Unmount binds BEFORE squashing ====================================
cleanup_mounts
rm -f "${CHROOT}/etc/resolv.conf"

# === 9. Squash the root filesystem =========================================
log "mksquashfs (packing the rootfs — the slow step under emulation)"
rm -f "${IMG}/casper/filesystem.squashfs"
# NOTE: do NOT exclude boot/ — keeping the kernel + initrd in the rootfs means a
# system installed to disk (via ubiquity) has a working /boot. proc/sys/dev/run
# are empty after the unmount above; excluding them is just hygiene.
mksquashfs "${CHROOT}" "${IMG}/casper/filesystem.squashfs" \
  -comp zstd -noappend -no-progress -wildcards \
  -e "proc/*" "sys/*" "dev/*" "run/*" "tmp/*"
printf '%s' "$(du -sx --block-size=1 "${CHROOT}" | cut -f1)" > "${IMG}/casper/filesystem.size"

# === 10. .disk metadata (casper looks for these) ===========================
echo "s4s-pc - Ubuntu 24.04 LTS \"Noble\" amd64 (with Vaultwarden)" > "${IMG}/.disk/info"
touch "${IMG}/.disk/base_installable"
echo "full_cd/single" > "${IMG}/.disk/cd_type"

# === 11. GRUB menu =========================================================
cat > "${IMG}/boot/grub/grub.cfg" <<'EOF'
set timeout=10
set default=0
menuentry "Try s4s-pc (live: worker desktop)" {
    linux  /casper/vmlinuz boot=casper quiet splash ---
    initrd /casper/initrd
}
menuentry "Install s4s-pc to disk (automated: root + worker)" {
    linux  /casper/vmlinuz boot=casper automatic-ubiquity file=/cdrom/preseed/ours.seed debian-installer/locale=en_US.UTF-8 keyboard-configuration/layoutcode=us quiet splash noprompt ---
    initrd /casper/initrd
}
menuentry "s4s-pc - safe graphics (nomodeset)" {
    linux  /casper/vmlinuz boot=casper quiet splash nomodeset ---
    initrd /casper/initrd
}
menuentry "Check disc for defects" {
    linux  /casper/vmlinuz boot=casper integrity-check quiet splash ---
    initrd /casper/initrd
}
EOF

# --- ubiquity preseed: install exactly root + non-admin 'worker' ------------
# Hash the passwords (SHA-512 crypt). worker is stripped from sudo and the
# polkit lockdown is installed in ubiquity/success_command (runs in-target).
ROOT_HASH="$(openssl passwd -6 "${ROOT_PASSWORD}")"
WORKER_HASH="$(openssl passwd -6 "${WORKER_PASSWORD}")"
mkdir -p "${IMG}/preseed"
cp "${ROOT}/overlay/etc/polkit-1/rules.d/00-restrict-software-install.rules" \
   "${IMG}/preseed/00-restrict-software-install.rules"
cat > "${IMG}/preseed/ours.seed" <<EOF
d-i debian-installer/locale            string en_US.UTF-8
d-i keyboard-configuration/layoutcode  string us
d-i console-setup/ask_detect           boolean false

# Installed-system primary user 'worker' (demoted to non-admin below).
d-i passwd/user-fullname        string Worker
d-i passwd/username             string worker
d-i passwd/user-password-crypted password ${WORKER_HASH}
d-i user-setup/allow-password-weak boolean true
d-i user-setup/encrypt-home     boolean false
d-i passwd/auto-login           boolean false
d-i passwd/user-default-groups  string

# Enable + set the root password (root is locked by default on Ubuntu).
d-i passwd/root-login           boolean true
d-i passwd/root-password-crypted password ${ROOT_HASH}

ubiquity ubiquity/summary       note
ubiquity ubiquity/reboot        boolean true

# After install: strip admin from worker + install the polkit lockdown in /target.
ubiquity ubiquity/success_command string \\
  in-target gpasswd -d worker sudo ; \\
  in-target gpasswd -d worker adm ; \\
  in-target deluser worker lpadmin || true ; \\
  in-target deluser worker sambashare || true ; \\
  mkdir -p /target/etc/polkit-1/rules.d ; \\
  cp /cdrom/preseed/00-restrict-software-install.rules /target/etc/polkit-1/rules.d/00-restrict-software-install.rules ; \\
  in-target chmod 644 /etc/polkit-1/rules.d/00-restrict-software-install.rules
EOF

# A tiny bootstrap config embedded into the standalone GRUB images: it locates
# the real medium (by the unique /.disk/info marker) and sources the menu above.
cat > "${WORK}/grub-embed.cfg" <<'EOF'
search --no-floppy --set=root --file /.disk/info
configfile ($root)/boot/grub/grub.cfg
EOF
# NOTE: do NOT 'set prefix' to the CD here — that makes GRUB look for its modules
# (linux.mod, etc.) on the CD, where they don't exist ("linux.mod not found").
# Leaving prefix at the built-in memdisk keeps module loading working; $root
# (set by search) is all the menu needs to find the kernel/initrd on the CD.

# === 12. Assemble the hybrid BIOS + UEFI ISO ===============================
log "building BIOS core image (grub i386-pc)"
# i386-pc has a hard core-image size cap: bundling ALL modules overflows it
# ("core image is too big"). Include only the modules the embedded config and
# the menu actually need (memdisk+tar are required by grub-mkstandalone itself).
BIOS_MODULES="memdisk tar normal iso9660 search search_fs_file configfile \
linux biosdisk part_gpt part_msdos fat ext2 echo test true ls cat halt reboot"
grub-mkstandalone \
  --format=i386-pc \
  --install-modules="${BIOS_MODULES}" \
  --modules="search iso9660 configfile normal" \
  --locales="" --fonts="" \
  --output="${WORK}/core.img" \
  "boot/grub/grub.cfg=${WORK}/grub-embed.cfg"
cat /usr/lib/grub/i386-pc/cdboot.img "${WORK}/core.img" > "${IMG}/boot/grub/bios.img"

log "building UEFI image (grub x86_64-efi -> efiboot.img FAT)"
# EFI has no core-size limit, but grub-mkstandalone's DEFAULT module set can omit
# iso9660/search_fs_file/test — without them the embedded config can't find the
# medium and drops to a `grub>` prompt. So list the modules explicitly.
EFI_MODULES="memdisk tar normal iso9660 search search_fs_file search_fs_uuid \
configfile linux echo test true ls cat halt reboot part_gpt part_msdos fat ext2 \
all_video efi_gop efi_uga gfxterm"
grub-mkstandalone \
  --format=x86_64-efi \
  --install-modules="${EFI_MODULES}" \
  --modules="search iso9660 configfile normal part_gpt fat" \
  --locales="" --fonts="" \
  --output="${WORK}/bootx64.efi" \
  "boot/grub/grub.cfg=${WORK}/grub-embed.cfg"
(
  cd "${WORK}"
  dd if=/dev/zero of=efiboot.img bs=1M count=10 status=none
  mkfs.vfat -n S4SEFI efiboot.img >/dev/null
  mmd   -i efiboot.img ::EFI ::EFI/BOOT
  mcopy -i efiboot.img bootx64.efi ::EFI/BOOT/BOOTX64.EFI
)
cp "${WORK}/efiboot.img" "${IMG}/EFI/boot/efiboot.img"

log "xorriso: producing ${ISO_NAME}"
xorriso -as mkisofs \
  -iso-level 3 -full-iso9660-filenames -volid "${VOLID}" \
  -eltorito-boot boot/grub/bios.img \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    --eltorito-catalog boot/grub/boot.cat \
    --grub2-boot-info --grub2-mbr /usr/lib/grub/i386-pc/boot_hybrid.img \
  -eltorito-alt-boot \
    -e EFI/boot/efiboot.img -no-emul-boot \
  -append_partition 2 0xef "${IMG}/EFI/boot/efiboot.img" \
  -output "${OUT}/${ISO_NAME}" \
  "${IMG}"

log "DONE"
ls -la "${OUT}/${ISO_NAME}"
echo "    Size: $(du -h "${OUT}/${ISO_NAME}" | cut -f1)"
