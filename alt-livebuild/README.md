# alt-livebuild — live-build variant (BIOS-only, reference)

This directory keeps the original **live-build** configuration you first asked
for. It is **not** the engine the project builds with by default. The primary
engine is `debootstrap` (see `../scripts/` and the top-level `README.md`),
because it produces a **BIOS + UEFI** image and wires up **Vaultwarden** — both
of which the Ubuntu live-build fork cannot do.

## Why it's not the default

Ubuntu ships an ancient live-build fork (`live-build 3.0~a57`). We verified in
the builder container that:

- its `lb config` uses **different flag names** than the Debian live-build
  manual (e.g. `--architectures`, singular `--bootloader`, `--debian-installer
  false`; no `--updates` / `--bootloaders` / `--uefi-secure-boot`); and
- it produces a **Legacy-BIOS-only** ISO — its `lb_binary_iso` stage uses
  `genisoimage` with BIOS El Torito and there is **no** `efi.img` / `grub-efi`
  / `bootx64.efi` code anywhere in the tool. So the resulting ISO will not boot
  on UEFI-only PCs.

It also does **not** preinstall Vaultwarden (that lives in the primary engine's
`overlay/`).

## If you still want to use it

You'd run it inside a similar privileged amd64 container with `live-build`
installed:

```sh
cd alt-livebuild
lb config        # reads auto/config (flags already corrected for 3.0~a57)
lb build         # produces a BIOS-only live-image-amd64.hybrid.iso
```

The `config/package-lists/*.list.chroot` here install GNOME + a desktop
password manager as a reference; adapt as needed. For anything real, prefer the
debootstrap engine.
