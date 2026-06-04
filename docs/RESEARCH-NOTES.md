# Обоснование решений (research notes)

Перед сборкой проводилось исследование с веб-поиском и **адверсариальной
проверкой** находок (8 агентов). Ниже — выводы, которые напрямую определили
архитектуру проекта, и факты, проверенные прямо в билдер-контейнере.

## Ключевые выводы

### 1. Ubuntu-шный `live-build` умеет только BIOS — поэтому движок debootstrap
Ubuntu поставляет древний форк `live-build 3.0~a57-1ubuntu49.1` (не современный
Debian live-build). Проверено прямо в контейнере:
- его `lb config` использует **другие имена флагов** (`--architectures`,
  единичный `--bootloader grub|syslinux|yaboot`, `--debian-installer false`; нет
  `--updates`, `--bootloaders`, `--uefi-secure-boot`);
- в нём **нет UEFI-кода вообще**: `grep` по `/usr/lib/live/build/` не находит
  `efi.img`, `eltorito-alt-boot`, `bootx64`, `grub-efi`; сборка ISO идёт через
  `genisoimage` с BIOS-only El Torito.

Вывод: для образа, который грузится на современных UEFI-ПК, нужен другой путь.
Выбран **debootstrap + casper + mksquashfs + grub-mkstandalone + xorriso** —
проверенный подход (mvallim/live-custom-ubuntu-from-scratch), дающий BIOS+UEFI.

### 2. `casper` обязателен явно
Даже в `--mode ubuntu` live-build не добавляет `casper` сам (Debian bug
#772522). Без него образ грузит ядро, но live-сессии нет. В debootstrap-движке
`casper` стоит явным пакетом в `chroot-setup.sh`. casper же создаёт live-юзера
`ubuntu` и настраивает автологин в gdm3 (скрипт `15autologin` правит
закомментированные строки `AutomaticLogin*` в `/etc/gdm3/custom.conf`).

### 3. Архитектуру задаём явно
На Apple Silicon арх. по умолчанию = arm64. Поэтому везде форсим amd64:
`FROM --platform=linux/amd64`, `docker run --platform=linux/amd64`,
`debootstrap --arch=amd64`. Иначе получился бы ARM-образ, не грузящийся на ПК.

### 4. Docker на Mac: privileged + mknod, без `-v /dev:/dev`
live-build/сборка ISO требует mount/chroot → контейнер `--privileged`. На Mac
**нельзя** монтировать `-v /dev:/dev` (это `/dev` от Darwin без Linux-loop'ов) —
loop-узлы создаются `mknod` внутри контейнера. Для плоского iso-hybrid loop'ы
почти не нужны (mksquashfs + xorriso их не требуют), но узлы создаются на всякий.

### 5. Эмуляция amd64 на Apple Silicon — медленно, но работает
QEMU/Rosetta в 3-10× медленнее нативного; полная сборка может идти 1-3+ часа.
Самый надёжный путь — нативный x86 (GitHub Actions). Это причина, по которой в
проекте есть CI-workflow.

### 6. «vaultpass» = Vaultwarden
Пакета `vaultpass` в репах Ubuntu нет (так зовутся лишь браузерные расширения).
Имелся в виду **Vaultwarden** — self-hosted Bitwarden-совместимый сервер,
штатно запускаемый в Docker (что и совпало с «типо в докере парольник»).

## Что добавила адверсариальная проверка (и что мы учли)

Проверка пометила исходные находки как «major-issues» и спасла от нерабочего
образа. Учтённые правки:
- **Clonezilla `create-ubuntu-live` использует live-boot, а не casper** — ссылка
  на него как на «каноничный casper-рецепт» была ошибкой; за основу взят
  mvallim (debootstrap, без live-build).
- **Apple Silicon / кросс-арх были полностью пропущены** в первой версии — теперь
  это центральная часть (platform, эмуляция, mknod).
- **`-v /dev:/dev` на Mac — вредный совет** (Darwin `/dev`); заменено на mknod.
- **`--uefi-secure-boot enable` жёстко падает** без подписанных пакетов.
- Нужна **генерация локали** в хуке (не только пакеты языка).

## Факты, проверенные прямо в контейнере (а не только из поиска)

| Проверка | Результат |
|----------|-----------|
| Имена пакетов noble (GNOME, docker-compose-v2, ubiquity 24.04.5, epiphany, polkitd, skopeo) | все существуют ✅ |
| `live-build` в Ubuntu — версия и опции | `3.0~a57`, BIOS-only ✅ (подтвердило вывод №1) |
| skopeo офлайн-бандл `vaultwarden/server` → docker-archive | 247 МБ, manifest ок ✅ |
| Сборка гибридного ISO (grub i386-pc + x86_64-efi + xorriso) | El Torito: BIOS **и** UEFI + GPT `0xef` ✅ |
| `grub-mkstandalone --format=i386-pc` со всеми модулями | «core image too big» ❌ → починено ограничением модулей |
| debootstrap noble + `apt-get install` в chroot под QEMU | ~2 мин база, maintainer-скрипты выполняются ✅ |

## Основные источники

- live-build manpage (noble) и Debian bug #772522 (casper в ubuntu mode)
- mvallim/live-custom-ubuntu-from-scratch (debootstrap + casper + xorriso)
- Clonezilla `create-ubuntu-live` (живой пример live-build для Ubuntu)
- casper `15autologin` / `25adduser` (Launchpad) — автологин live-юзера
- packages.ubuntu.com/noble (имена и компоненты пакетов)
- moby/moby#27886 (Docker /dev и loop-устройства)
- Vaultwarden (dani-garcia/vaultwarden) — деплой через Docker/compose
