# ============================================================================
# s4s-pc — ISO builder image (debootstrap engine).
#
# Pinned to amd64 so the chroot and the resulting ISO are x86_64 — even when
# built on an Apple Silicon (arm64) Mac (it then runs under emulation; slow).
# On a native x86_64 host / CI runner this is just native and fast.
# ============================================================================
# hadolint ignore=DL3029
FROM --platform=linux/amd64 ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Tooling the build shells out to:
#   debootstrap      - bootstraps the Ubuntu base into a chroot
#   squashfs-tools   - mksquashfs (packs the root filesystem)
#   xorriso          - assembles the hybrid BIOS+UEFI ISO
#   grub-pc-bin      - i386-pc GRUB modules (Legacy BIOS boot)
#   grub-efi-amd64-bin - x86_64-efi GRUB modules (UEFI boot)
#   grub-common      - grub-mkstandalone
#   mtools/dosfstools- build the FAT EFI System Partition image (efiboot.img)
#   skopeo           - bundle the Vaultwarden docker image offline (no daemon)
RUN apt-get update && apt-get install -y --no-install-recommends \
        debootstrap \
        squashfs-tools \
        xorriso \
        grub-pc-bin \
        grub-efi-amd64-bin \
        grub-common \
        mtools \
        dosfstools \
        skopeo \
        ubuntu-keyring \
        ca-certificates curl gnupg openssl \
        util-linux \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY . /build
RUN chmod +x /build/scripts/*.sh 2>/dev/null || true

ENTRYPOINT ["/build/scripts/entrypoint.sh"]
