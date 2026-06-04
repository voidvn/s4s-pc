# Hardening: users, auditing, network logging, decoy vault

This image is a **monitored, locked-down workstation**: two fixed accounts, a
non-admin daily user, comprehensive auditing with ~6-month retention, and a
Vaultwarden decoy vault. All of it is transparent system configuration applied
at build time.

## 1. Users — `root` + non-admin `worker`

| Account | Rights | Set where |
|---------|--------|-----------|
| `root` | admin (console/`su` only; GDM blocks root GUI login) | password in chroot + preseed |
| `worker` | **no sudo, no docker** — cannot install software | autologin in live; preseed on install |

- Passwords come from build vars **`ROOT_PASSWORD` / `WORKER_PASSWORD`** (default
  `root` / `worker` — **change them**): `ROOT_PASSWORD=… WORKER_PASSWORD=… ./build.sh build`,
  or set repo secrets `ROOT_PASSWORD` / `WORKER_PASSWORD` for the CI build.
- **Live session**: `worker` autologins (via `/etc/casper.conf`). casper tries to
  grant the live user sudo; `s4s-lock-worker.service` strips it back off every boot.
- **Installed system**: the `Install s4s-pc to disk (automated: root + worker)`
  GRUB entry runs ubiquity with `preseed/ours.seed` → creates exactly root + worker,
  then `ubiquity/success_command` removes worker from sudo/adm and installs the
  polkit lockdown. No extra admin account is created.
- **Can't install software**: `worker` isn't in sudo (apt/dpkg are root-only) and
  `/etc/polkit-1/rules.d/00-restrict-software-install.rules` denies the GUI/D-Bus
  path (PackageKit/GNOME Software, snap, flatpak, fwupd, pkexec) to non-sudo users.
  Named `00-` so it sorts before vendor polkit rules.

## 2. Host auditing — auditd (“who edited what, when”)

- `auditd` + `audispd-plugins` with a Neo23x0-style ruleset in
  `/etc/audit/rules.d/`: file-modification syscalls (chmod/chown/rename/unlink +
  `-w /etc -p wa`, `-w /home -p wa`), `execve` (commands run), logins, sudo,
  identity changes. The `auid` field is the login user (survives `su`/`sudo`).
- Read it back:
  ```bash
  sudo ausearch -k etc_changes -i -ts today      # who changed files under /etc today
  sudo ausearch -f /etc/passwd -i                 # everything touching a file
  sudo ausearch -k process_creation -ua worker -i # commands worker ran
  sudo aureport -f -i                             # file-change summary
  sudo auditctl -s                                # health (lost should be 0)
  ```
- Rules are mutable (`-e 1`); switch `99-finalize.rules` to `-e 2` for tamper-resistance.

## 3. Network / web-request logging — Zeek + OpenSnitch

- **Zeek** (from the openSUSE OBS repo; not in Ubuntu) sniffs the primary NIC and
  logs **web requests in/out**:
  - `http.log` — method / host / URI / status of every cleartext HTTP request
  - `ssl.log` — `server_name` (SNI) = the hostname of each HTTPS request
  - `conn.log` — every connection 4-tuple; `dns.log` — resolved names
  - Logs in `/opt/zeek/logs` (current/ + dated gzip archives), interface resolved
    at boot by `zeek.service`.
- **OpenSnitch** (in noble universe) logs **every outbound connection per process**
  to `/var/lib/opensnitchd/opensnitch.db`, default action allow+log (no blocking).
  The GUI (`opensnitch-ui`) autostarts in the desktop session.

## 4. Retention — ~6 months

| Source | Mechanism |
|--------|-----------|
| auditd | `keep_logs` + `logrotate maxage 183` (delete rotated logs >183 days) |
| journald | persistent, `MaxRetentionSec=15768000` (26 weeks), capped `SystemMaxUse=4G` |
| Zeek | `LogExpireInterval = 182 day` in `zeekctl.cfg`, driven by `zeek-cron.timer` |
| OpenSnitch | `opensnitch-prune.timer` deletes DB rows older than 182 days |

> ⚠️ Disk: 6 months of “log everything” on a busy box can reach tens of GB. Put
> `/var/log`, `/opt/zeek/logs`, `/var/lib/opensnitchd` on a sized volume.

## 5. Vaultwarden decoy — autofill-only fake-site logins

**Goal**: `worker` can autofill the fake-site logins but cannot view/copy the
password. Mechanism: a Bitwarden **Organization** collection shared to worker with
the **“Hide Passwords”** permission (`readOnly + hidePasswords`).

> ⚠️ **This is a soft / anti-shoulder-surfing control, NOT a security boundary.**
> Autofill still delivers the cleartext to worker’s browser — a technical user can
> read it via devtools (`input.value`), the sync response, or `bw` with their own
> creds. Use Vaultwarden **v1.35.0+** (fixes the “edit, hidden passwords” bypass).

Headless setup is fragile (`bw` can’t create an org; CLI `--raw`/confirm bugs), so
do it **once** via the web vault (`http://localhost:8080`):

1. Create your **owner** account; create the **worker** account too.
2. Create an **Organization** (e.g. “Decoys”) → a **Collection** “Worker Logins”.
3. **Import** the decoys: Tools → Import → *Bitwarden (json)* →
   `/opt/vaultwarden/fake-sites.json`; move them into the collection.
4. **Invite** worker to the org (no SMTP → auto-accepts) and **Confirm** them.
5. On the collection’s member access for worker, tick **Hide Passwords**.

The `bw`-scriptable subset (collection + items + confirm + hide-passwords flag,
once the org exists) is in `/opt/vaultwarden/provision.sh` — read its header first.

Verify as worker: the fake logins autofill on their sites, but the password field
shows `••••` and reveal/copy are blocked.
