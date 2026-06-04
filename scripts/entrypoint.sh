#!/bin/bash
set -euo pipefail

# ============================================================================
# s4s-pc build entrypoint — runs INSIDE the privileged amd64 builder container.
#
#   MODE=build  (default)  full build  -> /build/out/*.iso
#   MODE=check             dry checks: tooling present, scripts parse, then exit
#
# Knobs (env, all optional):
#   VW_MODE=offline|pull   how Vaultwarden's docker image gets into the ISO
#   SUITE=noble            Ubuntu suite
#   ISO_NAME=...           output file name
# ============================================================================
MODE="${MODE:-build}"

echo "==> s4s-pc builder | arch=$(uname -m) | MODE=${MODE} | VW_MODE=${VW_MODE:-offline}"

# --- Docker /dev workaround -------------------------------------------------
# Docker snapshots /dev at container start and doesn't sync loop devices that
# get created later. Pre-create the nodes against the VM kernel. (We do NOT
# bind-mount the host /dev — on a Mac that is Darwin's /dev with no Linux loops.)
for i in $(seq 0 15); do
  [ -e "/dev/loop${i}" ] || mknod -m 0660 "/dev/loop${i}" b 7 "${i}" 2>/dev/null || true
done
[ -e /dev/loop-control ] || mknod -m 0660 /dev/loop-control c 10 237 2>/dev/null || true

if [ "${MODE}" = "check" ]; then
  echo "==> check: required tools"
  for t in debootstrap mksquashfs xorriso grub-mkstandalone mkfs.vfat mcopy skopeo; do
    if command -v "$t" >/dev/null 2>&1; then echo "  OK   $t"; else echo "  MISS $t"; exit 1; fi
  done
  echo "==> check: scripts parse"
  bash -n /build/scripts/build-iso.sh && echo "  OK   build-iso.sh"
  bash -n /build/scripts/chroot-setup.sh && echo "  OK   chroot-setup.sh"
  echo "==> check passed."
  exit 0
fi

exec /build/scripts/build-iso.sh
