# Remote access: RustDesk + Wake-on-LAN

The image bakes in **RustDesk** (remote desktop, via public relays) and a
**Wake-on-LAN** service so office machines can be powered on, connected to, and
shut down from a personal PC.

## RustDesk

**What's baked in:**
- Latest stable RustDesk `.deb` (fetched from GitHub at build time).
- The `rustdesk` **systemd service runs as root** → provides *incoming* unattended
  access regardless of who is logged in.
- **GDM forced to Xorg** (`WaylandEnable=false`): RustDesk unattended capture/input
  does **not** work under Wayland (connects but black screen + dead input).
- A **first-boot** oneshot (`rustdesk-firstboot.service`) sets, per device:
  - the permanent password (from build var/secret `RUSTDESK_PASSWORD`),
  - `verification-method=use-permanent-password`, `approve-mode=password`
    (auto-accept, no manual click), and
  - `allow-logon-screen-password=Y` (lets you sign in at the GDM screen after a
    Wake-on-LAN boot, before anyone is at the machine).
- Public RustDesk relays (no self-host). E2E-encrypted; traffic transits RustDesk
  infra. To switch to your own server later, set `custom-rendezvous-server` /
  `relay-server` / `key` in `/root/.config/rustdesk/RustDesk2.toml`.

**Set the password (required for unattended access):**
```bash
RUSTDESK_PASSWORD='a-strong-password' ROOT_PASSWORD=… WORKER_PASSWORD=… ./build.sh build
# or set the repo secret RUSTDESK_PASSWORD for the CI build
```
> If `RUSTDESK_PASSWORD` is empty, RustDesk is installed but **no unattended
> password is set** (incoming access not pre-configured) — deliberate, so the image
> never ships a weak shared remote password. With public relays, anyone who learns
> a machine's ID + this password can connect — use a strong one.

**Connect:** each machine has a unique **ID** (derived from its per-machine
`/etc/machine-id`, generated on first boot — that's why we don't bake a config).
Read a machine's ID at setup time from the RustDesk window, or at a console:
```bash
sudo rustdesk --get-id        # also saved to /var/log/rustdesk-id.txt
```
Then from your personal PC's RustDesk client: enter the ID + the permanent password.

**Can `worker` use it?** Yes — `worker` can launch the RustDesk app and connect
*out* to other machines (normal app, no admin). The *incoming* service runs as root,
so `worker` (non-sudo) cannot disable it or change its password.

## Wake-on-LAN (power on remotely)

`wake-on-lan.service` arms magic-packet WoL on the wired NIC at every boot and
re-arms it at shutdown (some Realtek NICs clear it on link-down).

**Required in BIOS/UEFI** (OS setting alone is not enough): enable *Wake on LAN /
Wake on PME / Power On by PCIe*; DISABLE *ErP/EuP/Deep Sleep* (they cut standby
power and kill wake-from-off); use **wired Ethernet** (Wi-Fi WoWLAN is unreliable).

**Find a machine's MAC while it's on** (you can't read it once off):
```bash
ip link            # the wired NIC's link/ether address
```
**Power it on** from another host on the **same LAN**:
```bash
wakeonlan AA:BB:CC:DD:EE:FF
```
Magic packets don't cross subnets, so to wake from **outside the office** you need
an always-on relay on the office LAN (a WoL-capable router, or a small always-on
box you reach by VPN/SSH and run `wakeonlan` from).

**Power off:** once connected (RustDesk or SSH), `systemctl poweroff` as root.

**Verify WoL is armed:** `sudo ethtool <iface> | grep Wake-on` → must show `Wake-on: g`.

> Don't run `powertop --auto-tune` or default TLP — both disable WoL.
