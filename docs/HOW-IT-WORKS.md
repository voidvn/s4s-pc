# Как это устроено

## Общая картина

```
  твой Mac (arm64)
  └─ docker build --platform=linux/amd64 ──────────────────────┐
                                                               ▼
           ┌────────────────────────────────────────────────────────────┐
           │  Docker-контейнер (amd64, под эмуляцией на Apple Silicon)    │
           │  образ: s4s-pc-builder:amd64                                 │
           │                                                              │
           │  scripts/entrypoint.sh → scripts/build-iso.sh:               │
           │   1. debootstrap   → минимальная база Ubuntu noble в chroot  │
           │   2. chroot-setup  → GNOME + Docker + Vaultwarden + ubiquity │
           │   3. skopeo        → офлайн-бандл образа vaultwarden/server  │
           │   4. mksquashfs    → chroot ⇒ /casper/filesystem.squashfs    │
           │   5. grub-mkstandalone ×2 → BIOS core.img + UEFI bootx64.efi │
           │   6. xorriso       → гибридный BIOS+UEFI ISO                 │
           └────────────────────────────────────────────────────────────┘
                                                               │
                                       out/s4s-pc-noble-amd64.iso (на хост)
```

Важно: **под эмуляцией идёт только сборка**. Сам ISO потом грузится на реальном
x86-железе нативно, так что Vaultwarden/Docker в работающей системе быстрые.

## Поток сборки по шагам (`scripts/build-iso.sh`)

1. **debootstrap** — качает минимальную базу Ubuntu noble (`--variant=minbase`,
   компоненты main/restricted/universe/multiverse) в каталог `work/chroot`.
2. **apt sources** — внутрь chroot пишется `sources.list` (noble + noble-updates
   + noble-security).
3. **bind-mount** — `/dev`, `/dev/pts`, `/proc`, `/sys`, `/run` пробрасываются в
   chroot; копируется `resolv.conf` для DNS.
4. **overlay/** — наши готовые файлы (systemd-юнит Vaultwarden, compose-файл,
   лаунчер, gschema-override, netplan) копируются в корень chroot как есть.
5. **skopeo** — если `VW_MODE=offline` (по умолчанию), образ
   `docker.io/vaultwarden/server:latest` (amd64) сохраняется в
   `/opt/vaultwarden/vaultwarden.tar` внутри chroot **без docker-демона**
   (skopeo умеет писать docker-archive напрямую). Это и есть «офлайн-бандл».
6. **chroot-setup.sh** — выполняется внутри chroot (см. ниже): ставит GNOME,
   Docker, Vaultwarden-обвязку и установщик, включает сервисы.
7. **kernel + initrd** — `vmlinuz`/`initrd.img` из chroot копируются в
   `image/casper/`; собирается `filesystem.manifest`.
8. **unmount** — bind-моунты снимаются (иначе `/proc` попал бы в squashfs).
9. **mksquashfs** — chroot пакуется в `image/casper/filesystem.squashfs`
   (компрессия zstd). Это самый долгий шаг под эмуляцией.
10. **.disk/** — метаданные носителя (casper ищет `/.disk/info`).
11. **grub.cfg** — меню загрузки (Try/Install, safe graphics, проверка диска).
12. **ISO** — два независимых загрузчика собираются в один гибридный образ:
    - **BIOS**: `grub-mkstandalone --format=i386-pc` → `core.img`, склеивается с
      `cdboot.img` → `bios.img` (El Torito для Legacy BIOS).
    - **UEFI**: `grub-mkstandalone --format=x86_64-efi` → `bootx64.efi`, который
      кладётся в FAT-образ `efiboot.img` как `/EFI/BOOT/BOOTX64.EFI`.
    - `xorriso -as mkisofs` собирает оба как две записи El Torito + добавляет
      GPT-раздел `0xef` (чтобы образ грузился по UEFI и с USB).

## Что делает `chroot-setup.sh` (внутри chroot)

- Локали (`locale-gen en_US.UTF-8`), hostname, `policy-rc.d` (чтобы демоны не
  стартовали во время установки в chroot).
- **Ядро + live**: `linux-generic`, `casper` (Ubuntu-овская live-сессия:
  создаёт юзера `ubuntu`, пустой пароль, sudo без пароля, автологин в gdm3).
- **GNOME** (кураторский набор, без snap): `gnome-shell`, `gdm3`,
  `gnome-settings-daemon`, `gnome-control-center`, `nautilus`,
  `xdg-desktop-portal-gnome`, `dbus-user-session`, `polkitd`,
  `gnome-shell-extension-ubuntu-dock`, тема Yaru, GNOME Web (epiphany).
- **Docker + Vaultwarden runtime**: `docker.io`, `docker-compose-v2`, `skopeo`.
- **Установщик**: `ubiquity` + `ubiquity-frontend-gtk` (значок «Install» на
  рабочем столе live-сессии для установки на диск).
- Включает сервисы: `gdm3`, `NetworkManager`, `docker`, `vaultwarden.service`;
  ставит цель по умолчанию `graphical.target`.
- Компилирует gschema-override (закрепление Vaultwarden в доке).
- `update-initramfs -u` — пересобирает initrd с хуками casper.

## Как поднимается Vaultwarden при загрузке

`vaultwarden.service` (Type=oneshot, после `docker.service`):

1. `ExecStartPre=/usr/local/bin/vaultwarden-load.sh`:
   - если это **live**-сессия (корень — overlayfs), переключает Docker на
     драйвер `vfs` (overlay2 не умеет работать поверх overlayfs) и
     перезапускает докер;
   - добавляет юзера `ubuntu` в группу `docker`;
   - `docker load` офлайн-бандла `vaultwarden.tar`, если образа ещё нет.
2. `ExecStart=docker compose up -d` (из `/opt/vaultwarden/docker-compose.yml`) —
   поднимает контейнер на `http://localhost:8080`.

Лаунчер `vaultwarden.desktop` (закреплён в доке) открывает этот адрес в браузере.

## Ключевые решения (и почему)

| Решение | Почему |
|---------|--------|
| движок **debootstrap**, не live-build | Ubuntu-шный live-build умеет только BIOS; debootstrap даёт BIOS+UEFI и полный контроль. |
| `casper` явно | Делает образ загружаемой live-сессией (создаёт юзера, автологин). |
| кураторский GNOME, **без snap** | snap-firefox в live-сессии виснет; в образе с Docker лишний слой overlay ни к чему. |
| **skopeo** для бандла VW | Пишет docker-archive без docker-демона прямо в chroot — чисто и офлайн. |
| Docker драйвер **vfs** в live | overlay2 не стыкуется поверх casper-овского overlayfs; на установленной системе остаётся overlay2. |
| `grub-mkstandalone` с **ограниченным** набором модулей для i386-pc | BIOS-ядро имеет жёсткий лимит размера; полный набор модулей его превышает. |
| `-append_partition 2 0xef` в xorriso | Добавляет EFI System Partition → UEFI-загрузка и с USB. |
