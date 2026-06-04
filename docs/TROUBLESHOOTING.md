# Грабли и решения

## Сборка

### Самый быстрый путь — нативный x86 (GitHub Actions)
На Apple Silicon сборка идёт под эмуляцией (медленно, иногда виснет на
maintainer-скриптах). Раннеры `ubuntu-24.04` в GitHub Actions — нативный amd64,
без эмуляции. Запушь репозиторий и запусти workflow `build-iso`
(вкладка Actions → Run workflow) → готовый ISO в артефактах за ~15-30 мин.

### «core image is too big» (grub i386-pc)
BIOS-ядро GRUB имеет жёсткий лимит размера. `grub-mkstandalone` по умолчанию
пакует все модули и превышает его. Решено в `build-iso.sh`: для `--format=i386-pc`
передаётся ограниченный `--install-modules`. Если добавляешь свои grub-модули —
держи набор маленьким.

### Сборка «зависла» на debootstrap / dpkg
Скорее всего это не зависание, а эмуляция QEMU (в 3-10× медленнее нативного).
Включи Rosetta (Docker Desktop → Settings → General), дай ВМ больше CPU/RAM.
Если действительно встало на конкретном пакете под эмуляцией — собери на CI.

### `losetup` / `mount: permission denied` в контейнере
Контейнер должен быть `--privileged` (так и запускает `build.sh`). На Mac **не**
монтируй `-v /dev:/dev` — это `/dev` от Darwin без Linux-loop'ов. Скрипт сам
делает `mknod /dev/loop*` против ядра VM.

### `exec format error` в chroot
Не зарегистрирован binfmt/qemu для amd64. На Docker Desktop эмуляция встроена —
просто собирай с `--platform=linux/amd64` (так делает `build.sh`). На «голом»
Linux-docker один раз: `docker run --privileged --rm tonistiigi/binfmt --install amd64`.

### Кончилось место
chroot + squashfs + ISO легко съедают 20-30 ГБ. Увеличь размер диска Docker
Desktop (Settings → Resources), почисти `work/` и старые образы (`docker system prune`).

### skopeo не смог скачать образ Vaultwarden
Нужен интернет на этапе сборки (офлайн-бандл качается во время билда). Если нет —
собери с `VW_MODE=pull` (тогда образ потянется при первой загрузке системы).

## Загрузка готового ISO

### Не грузится на современном ПК
Проверь, что собирал **debootstrap**-движком (out/s4s-pc-noble-amd64.iso), а не
`alt-livebuild` (тот только BIOS). Этот образ — BIOS+UEFI. В прошивке можно
оставить и UEFI, и Legacy.

### Чёрный экран после загрузки (нет GNOME)
Обычно не хватает 3D/видео в ВМ. Загрузись пунктом меню **«safe graphics
(nomodeset)»**, либо включи 3D-ускорение в ВМ, дай 4 ГБ+ RAM. На реальном железе
обычно всё ок.

### Secure Boot отказывается грузить
Образ собран с **неподписанным** GRUB. На ПК с включённым Secure Boot либо
выключи Secure Boot в прошивке, либо собери с подписанной цепочкой
shim+grub (добавь `grub-efi-amd64-signed`, `shim-signed` и подложи их в EFI —
это отдельная доработка).

## Vaultwarden в работе

### В live-сессии Vaultwarden не поднялся
Docker в live использует драйвер `vfs` (overlay2 не работает поверх overlayfs).
Это требует RAM: дай ВМ/ПК **4-8 ГБ**. Проверь:
```bash
systemctl status vaultwarden        # статус юнита
journalctl -u vaultwarden -b        # лог запуска
docker ps                           # контейнер vaultwarden поднят?
docker logs vaultwarden
```

### Данные пропали после перезагрузки
В **live**-сессии запись идёт в RAM-оверлей — это ожидаемо. Для постоянного
хранилища **установи систему на диск** (значок «Install»). Тогда
`/opt/vaultwarden/data` лежит на диске и сохраняется.

### Веб-хранилище не открывается на localhost:8080
Подожди ~10-30 сек после входа (контейнер стартует после `docker.service`).
Затем `docker ps`. Если порт занят — поменяй маппинг в `docker-compose.yml`.

### Хочу доступ с телефона/других устройств
Localhost-HTTP виден только на самом ПК. Для сети нужен HTTPS (Bitwarden-клиенты
требуют TLS): задай `DOMAIN` и поставь reverse-proxy с сертификатом —
см. [CUSTOMIZE.md](CUSTOMIZE.md).

## Если live-build всё-таки нужен
См. [`alt-livebuild/README.md`](../alt-livebuild/README.md). Помни: он даёт
**только BIOS** и **не** ставит Vaultwarden.
