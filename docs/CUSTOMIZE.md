# Кастомизация образа

Всё описано кодом. Ниже — частые задачи.

## Добавить программы (apt-пакеты)

Открой `scripts/chroot-setup.sh` и допиши пакеты в подходящий `apt-get install`.
Например, добавить редактор и плеер:

```sh
echo "==> [chroot] extra apps"
apt-get install -y --no-install-recommends \
  vlc gimp libreoffice-writer
```

> Совет: держи `--no-install-recommends`, чтобы не раздувать ISO, но проверяй,
> что приложение запускается (иногда нужный плагин лежит в Recommends).

## Положить свои файлы / настройки в систему

Любой файл из `overlay/` копируется в корень будущей системы **как есть**.
Структура `overlay/` повторяет файловую систему:

```
overlay/etc/skel/.config/...        → дефолтные настройки для новых юзеров
overlay/usr/share/applications/...  → свои .desktop-лаунчеры
overlay/etc/...                     → системные конфиги
```

Например, свой обои/дотфайлы для пользователя live-сессии: положи в
`overlay/etc/skel/` (casper-юзер `ubuntu` создаётся из `/etc/skel`).

## Поменять, что закреплено в доке GNOME

Правь `overlay/usr/share/glib-2.0/schemas/90_s4s_favorites.gschema.override`
(список `favorite-apps`, по ID `.desktop`-файлов). После правки пересобери —
`chroot-setup.sh` сам вызовет `glib-compile-schemas`.

## Настроить Vaultwarden

Файл `overlay/opt/vaultwarden/docker-compose.yml`:

- **Закрыть регистрацию** после создания своего аккаунта:
  `SIGNUPS_ALLOWED: "false"`.
- **Сменить порт**: `ports: ["8200:80"]` (и поправь URL в
  `overlay/usr/share/applications/vaultwarden.desktop`).
- **Включить админку**: добавь `ADMIN_TOKEN: "<длинный-секрет>"` → панель на
  `/admin`.
- **HTTPS / доступ из сети**: задай `DOMAIN: "https://host"` и поставь впереди
  reverse-proxy (Caddy/Nginx) с сертификатом, либо смонтируй сертификаты и задай
  `ROCKET_TLS`. Для одного ПК localhost-HTTP достаточно.

Тянуть образ при первой загрузке вместо офлайн-бандла:

```bash
VW_MODE=pull ./build.sh build
```

## Поменять парольник на другой

Vaultwarden — это **сервер**. Если хочется десктопный GUI-клиент вместо/в
дополнение к веб-хранилищу:

- **KeePassXC** (десктопный, формат .kdbx, есть в universe): добавь `keepassxc`
  в `chroot-setup.sh`.
- **Bitwarden desktop**: в репах Ubuntu нет. Положи вендорский `.deb` в
  `overlay/` или ставь по сети в хуке.
- **pass** (CLI): добавь пакет `pass`.

## Сменить версию Ubuntu

`SUITE` пробрасывается в `scripts/build-iso.sh`. Для другой LTS:

```bash
docker run ... -e SUITE=jammy ...   # 22.04
```

(Проверь имена пакетов GNOME/ubiquity для целевого релиза.)

## Изменить меню загрузки / параметры ядра

Правь heredoc `grub.cfg` в `scripts/build-iso.sh` (секция «GRUB menu»).
Например, убрать `quiet splash` для отладочного вывода, или добавить
`toram` (загрузка целиком в RAM).

## Убрать установщик (только live)

Закомментируй блок `ubiquity` в `scripts/chroot-setup.sh` — получится чисто
live-образ, чуть меньше по размеру.
