# s4s-pc — кастомный ISO Ubuntu 24.04 (GNOME) с предустановленным Vaultwarden

Проект собирает **загрузочный live-ISO Ubuntu 24.04 LTS (noble)** с окружением
**GNOME**, который грузится и на **UEFI**, и на **Legacy BIOS**, с предустановленным
менеджером паролей **Vaultwarden** (запускается в Docker, доступ через браузер).
Можно как попробовать с флешки, так и **установить на диск**. Всё описано
кодом — образ воспроизводим и собирается одной командой.

```
┌─────────────────────────────────────────────────────────────┐
│  Docker (на твоём Mac/ПК)                                     │
│    debootstrap → chroot (GNOME + Docker + Vaultwarden)        │
│    → mksquashfs → xorriso → гибридный BIOS+UEFI ISO           │
└─────────────────────────────────────────────────────────────┘
                          │
              out/s4s-pc-noble-amd64.iso  →  флешка / ВМ / установка на диск
```

> **Почему Vaultwarden, а движок — debootstrap, а не live-build?**
> «vaultpass / чет типа такого, типо в докере парольник» — это **Vaultwarden**:
> self-hosted Bitwarden-совместимый сервер, штатно живущий в Docker. А Ubuntu-шный
> `live-build` (проверено) умеет **только BIOS** — поэтому образ собирается
> через `debootstrap`, что даёт нормальный **BIOS+UEFI**. Вариант на live-build
> сохранён в [`alt-livebuild/`](alt-livebuild/README.md). Подробности —
> [docs/RESEARCH-NOTES.md](docs/RESEARCH-NOTES.md).

---

## TL;DR

```bash
cd /Users/void/GolandProjects/s4s-pc

# Быстрая проверка билдера (инструменты + синтаксис скриптов), без сборки:
./build.sh check

# Полная сборка ISO (на Apple Silicon — эмуляция x86, может занять 1-3+ часа):
./build.sh build
# готовый образ -> ./out/s4s-pc-noble-amd64.iso
```

⚡️ **Самый быстрый и надёжный путь** — собрать на нативном x86_64 раннере через
**GitHub Actions** (`.github/workflows/build-iso.yml`): запушил → получил готовый
ISO в артефактах за ~15-30 минут, без эмуляции. См.
[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

---

## Что внутри образа

| Компонент | Реализация |
|-----------|-----------|
| База | Ubuntu 24.04 LTS (noble), **amd64** |
| Окружение | **GNOME** (кураторский набор без snap), `gdm3`, автологин |
| Загрузка | гибридный ISO: **UEFI + Legacy BIOS**, `dd`-абельный на USB |
| Парольник | **Vaultwarden** в Docker, автозапуск при загрузке → `http://localhost:8080` |
| Поставка образа VW | офлайн-бандл в ISO (через `skopeo`) — работает без интернета |
| Браузер | GNOME Web (epiphany), без snap |
| Установка на диск | установщик **ubiquity** + preseed (ровно `root` + `worker`) |
| Сеть | NetworkManager |
| **Юзеры** | `root` (админ) + `worker` (без sudo/docker — не может ставить софт) |
| **Аудит хоста** | `auditd` — кто/что/когда правил файлы, какие команды, логины |
| **Сетевой лог** | **Zeek** (URL'ы веб-запросов in/out) + **OpenSnitch** (соединения по приложениям) |
| **Хранение логов** | ~6 месяцев (auditd/journald/Zeek/OpenSnitch retention) |
| **Decoy-парольник** | фейк-логины в Vaultwarden с «Hide Passwords» (autofill, но не показать) |
| **Удалёнка** | **RustDesk** (публ. релеи, безатендный пароль) + **Wake-on-LAN** (вкл/выкл удалённо) |
| **Wi-Fi/драйверы** | linux-firmware + modules-extra (универсально, без модели) |
| **Софт** | LibreOffice, VS Code, GIMP, Chrome, Firefox, Opera, Yandex, VLC, Node.js, Postman, Claude Code |

После загрузки Vaultwarden закреплён в доке GNOME — клик открывает веб-хранилище
в браузере. Первый аккаунт создаётся прямо в веб-интерфейсе (`SIGNUPS_ALLOWED=true`).

---

## Требования

- **Docker** (Docker Desktop на Mac). Проверено на Docker 29.x.
- ~**25-35 ГБ** свободного места (chroot + squashfs + ISO + кэш).
- Apple Silicon: включи **Rosetta** (Docker Desktop → Settings → General →
  «Use Rosetta for x86/amd64 emulation») — ускоряет эмуляцию.

---

## Команды

```bash
./build.sh check               # проверить билдер, без сборки
./build.sh build               # собрать ISO -> out/
VW_MODE=pull ./build.sh build  # не зашивать образ VW, тянуть при 1-й загрузке
make help                      # список make-таргетов
make shell                     # root-шелл внутри билдера (отладка)
```

---

## Структура проекта

```
s4s-pc/
├── README.md                      ← вы здесь
├── Dockerfile                     ← amd64 билдер: debootstrap, xorriso, grub, skopeo
├── build.sh                       ← запуск с хоста (docker build + run --privileged)
├── Makefile
├── scripts/
│   ├── entrypoint.sh              ← внутри контейнера: mknod loop, режимы check/build
│   ├── build-iso.sh               ← ★ debootstrap → squashfs → BIOS+UEFI ISO
│   └── chroot-setup.sh            ← ★ внутри chroot: GNOME + Docker + VW + установщик
├── overlay/                       ← файлы, кладущиеся в систему как есть
│   ├── etc/systemd/system/vaultwarden.service      ← автозапуск VW
│   ├── opt/vaultwarden/docker-compose.yml          ← описание контейнера VW
│   ├── usr/local/bin/vaultwarden-load.sh           ← загрузка образа + vfs для live
│   ├── usr/share/applications/vaultwarden.desktop  ← лаунчер (открыть localhost:8080)
│   ├── usr/share/glib-2.0/schemas/…override        ← закрепление VW в доке GNOME
│   └── etc/netplan/01-network-manager-all.yaml     ← сеть через NetworkManager
├── .github/workflows/build-iso.yml ← сборка на нативном x86 (рекомендуется)
├── alt-livebuild/                  ← запасной вариант на live-build (BIOS-only)
└── docs/
    ├── HOW-IT-WORKS.md             ← как устроена сборка, по шагам
    ├── HARDENING.md                ← юзеры, аудит, сетевой лог, decoy-парольник
    ├── CUSTOMIZE.md                ← добавить программы / настройки / поменять VW
    ├── TROUBLESHOOTING.md          ← грабли и решения
    └── RESEARCH-NOTES.md           ← обоснование решений + источники
```

> 🔐 **Пароли по умолчанию `root`/`worker` — обязательно поменяй:**
> `ROOT_PASSWORD=… WORKER_PASSWORD=… ./build.sh build` (или секреты репо для CI).
> Подробно про аудит, lockdown и decoy-хранилище — [docs/HARDENING.md](docs/HARDENING.md).

---

## Проверить готовый ISO

```bash
# UEFI (нужны qemu + OVMF):
qemu-system-x86_64 -m 4G -cdrom out/s4s-pc-noble-amd64.iso \
  -bios /usr/share/OVMF/OVMF_CODE.fd

# Legacy BIOS:
qemu-system-x86_64 -m 4G -cdrom out/s4s-pc-noble-amd64.iso

# На флешку: balenaEtcher (просто), или dd (на Linux: of=/dev/sdX bs=4M)
```

> ⚠️ Чтобы Vaultwarden (Docker) поднялся в **live**-сессии, дай ВМ/ПК **4-8 ГБ
> RAM** — в live-режиме запись идёт в RAM-оверлей, и Docker использует драйвер
> `vfs`. При установке на диск всё работает штатно и постоянно.

---

## Важные оговорки

1. **Apple Silicon = эмуляция.** Целевой образ x86_64 собирается под QEMU/Rosetta:
   медленно (часы), изредка подвисает на maintainer-скриптах. Для скорости —
   GitHub Actions или нативный x86. Тест показал: chroot под эмуляцией работает,
   просто небыстро.
2. **Vaultwarden в live — для демо.** Данные в live-сессии живут в RAM и
   пропадают после перезагрузки. Постоянное хранилище — после установки на диск
   (`/opt/vaultwarden/data`).
3. **HTTP на localhost.** По умолчанию веб-хранилище на `http://localhost:8080`.
   Для доступа из сети нужен HTTPS/reverse-proxy — см.
   [docs/CUSTOMIZE.md](docs/CUSTOMIZE.md).

Дальше: [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md).
