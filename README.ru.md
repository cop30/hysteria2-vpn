[English](README.md) | **Русский**

# Самостоятельный сервер Hysteria 2

[![Тесты](https://github.com/cop30/hysteria2-vpn/actions/workflows/test.yml/badge.svg)](https://github.com/cop30/hysteria2-vpn/actions/workflows/test.yml)
[![Релиз](https://img.shields.io/github/v/release/cop30/hysteria2-vpn)](https://github.com/cop30/hysteria2-vpn/releases/latest)
[![Лицензия: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Проект собирает Hysteria 2 из закреплённого upstream commit непосредственно на
VPS и запускает его через Docker Compose. Серверные секреты, клиентские URI,
QR-коды и резервные копии создаются на VPS и исключены из Git.

Это воспроизводимая и проверяемая альтернатива непрозрачному однострочному
установщику: исходный код upstream закреплён, изменения проверяются до
активации, а предыдущая версия остаётся доступной для отката. Проект не
заменяет защиту самого VPS.

## Быстрый старт

```bash
git clone https://github.com/cop30/hysteria2-vpn.git
cd hysteria2-vpn
sudo ./docker-install.sh
sudo INITIAL_CLIENT=iphone ./deploy.sh
```

Проверено на Ubuntu 24.04. Рекомендуемые клиенты: v2RAGE для iOS и Hiddify для
Windows. Перед импортом созданного QR-кода прочитайте раздел
[«Проверенные приложения-клиенты»](#проверенные-приложения-клиенты).

## Что делает проект

- закрепляет релиз и неизменяемый commit в `versions.conf`, поэтому повторный
  deploy не обновляет Hysteria незаметно;
- создаёт отдельный логин и пароль для каждого устройства;
- проверяет новую конфигурацию в контейнере без сети и откатывает неудачное
  изменение;
- запускает read-only контейнер без Linux capabilities, с
  `no-new-privileges` и ограничениями памяти/PID;
- использует UDP, поэтому Hysteria может занимать `443/udp`, пока другой сервис
  использует `443/tcp`;
- добавляет правило UFW и удаляет его при cleanup только тогда, когда правило
  создал сам проект.

По умолчанию: публичный `443/udp`, Salamander, IPv4-выход и самоподписанный
сертификат с SHA-256 pin в каждой клиентской ссылке.

## Архитектура

```text
Интернет-клиент
      │ Hysteria 2 + QUIC + Salamander, UDP/<публичный порт>
      ▼
UFW / firewall провайдера
      ▼
Docker publish: <публичный порт>/udp → 8443/udp
      ▼
read-only контейнер hysteria2 → прямой IPv4-выход в интернет
```

| Элемент | Назначение | Секретный |
|---|---|---|
| `versions.conf` | закреплённые релиз и commit | нет |
| `Dockerfile` | сборка Hysteria из исходников | нет |
| `docker-compose.yml.tmpl` | ограничения и запуск контейнера | нет |
| `state/` | сертификат, ключ, auth и runtime-конфигурация | **да** |
| `clients/` | URI и QR клиентов | **да** |
| `backups/` | локальные резервные копии | **да** |

Каталоги `state/`, `clients/`, `backups/` и сгенерированный
`docker-compose.yml` исключены из Git.

## Требования

- Ubuntu 24.04 или новее;
- root или sudo;
- `git`, `curl`, `openssl`, `iproute2`, `util-linux`;
- Docker Engine, Compose v2 и buildx;
- `qrencode`, если нужны PNG и вывод QR-кода в терминал;
- открытый UDP-порт в UFW и в фаерволе/панели VPS-провайдера;
- около 1,5 ГБ RAM или swap на время сборки. В рантайме требуется заметно
  меньше.

На маленькой VPS заранее добавьте swap. Не делайте это, если swap уже есть:

```bash
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

Проверка ресурсов:

```bash
free -h
df -h /
sudo docker system df
```

### Установка Docker

Если Docker ещё не установлен:

```bash
sudo ./docker-install.sh
```

Скрипт адаптирован из MIT-проекта
[`seb0ch/vpn`](https://github.com/seb0ch/vpn) и устанавливает `docker.io`,
`docker-compose-v2` и `docker-buildx` из штатных репозиториев Ubuntu. Он не
добавляет сторонний apt-репозиторий или GPG-ключ, пропускает уже установленные
компоненты и отказывается смешивать Ubuntu `docker.io` с обнаруженным стеком
`docker-ce`/`containerd.io`. Подробная атрибуция — в
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

Установщик Docker **не защищает VPS** и не меняет SSH, UFW или облачный
фаервол.

### Установка qrencode

Без `qrencode` сервер и файл `.hy2` работают, но PNG и QR в терминале не
создаются:

```bash
sudo apt-get update
sudo apt-get install -y qrencode
qrencode --version
```

## Установка Hysteria 2

Для публичного репозитория:

```bash
git clone https://github.com/cop30/hysteria2-vpn.git
cd hysteria2-vpn
sudo ./docker-install.sh       # только если Docker отсутствует
sudo apt-get install -y qrencode
sudo INITIAL_CLIENT=iphone ./deploy.sh
```

`deploy.sh`:

1. проверяет зависимости, релиз и закреплённый commit;
2. генерирует сертификат, Salamander secret и пароль первого клиента;
3. собирает Hysteria из исходников на VPS;
4. проверяет конфигурацию в изолированном временном контейнере;
5. открывает выбранный UDP-порт в активном UFW;
6. запускает Compose и проверяет контейнер и UDP-listener;
7. создаёт `.hy2`, проверяет, что файл непустой, создаёт PNG и печатает QR в
   терминал, если установлен `qrencode`.

Тяжёлые загрузки и сборка идут на VPS. Явно задать адрес, порт и SNI можно так:

```bash
sudo PUBLIC_HOST=vpn.example.com HYSTERIA_PORT=443 \
  TLS_SNI=vpn.example.com INITIAL_CLIENT=iphone ./deploy.sh
```

## Клиенты и QR-коды

```bash
sudo ./add-client.sh windows
sudo ./add-client.sh iphone-15
sudo ./remove-client.sh old-phone
```

Имя: 1–32 символа, латинские буквы, цифры, `_` и `-`. У каждого устройства
должен быть отдельный клиент: отзыв одного не ломает остальные.

После создания клиента скрипт проверяет `clients/<name>.hy2`. При наличии
`qrencode` он также проверяет `clients/<name>.png` и сразу печатает секретный QR
на экран. Эти файлы имеют режим `0600` и исключены из Git.

Показать существующий клиент повторно:

```bash
sudo qrencode -t ANSIUTF8 -r clients/iphone.hy2
```

Создать PNG для клиента, появившегося до установки `qrencode`:

```bash
sudo qrencode -s 8 -o clients/iphone.png -r clients/iphone.hy2
sudo chmod 0600 clients/iphone.png
```

QR и `.hy2` дают полный доступ к VPN: не публикуйте их в чате, Git, логах или
документации. IPv6 включайте только после проверки IPv6-выхода VPS.

### Проверенные приложения-клиенты

- **iOS:** [v2RAGE в российском App Store](https://apps.apple.com/ru/app/v2rage/id6761075402).
  Импортируйте созданный `.hy2` URI или отсканируйте QR-код. Тесты через
  мобильную сеть и проводного провайдера прошли стабильно с голландским и
  финским серверами Hysteria 2.
- **Windows:** [Hiddify](https://github.com/hiddify/hiddify-app/releases).
  Импортируйте тот же URI или QR-код. Продолжительные тесты через раздачу
  интернета с iPhone и проводного провайдера прошли стабильно.

Это практические рекомендации по результатам тестирования, а не гарантия для
любого устройства, оператора, провайдера или будущей версии приложения.
Обновляйте клиент и проверяйте его в реально используемых сетях. Не меняйте
только в клиенте порт: `443/udp` должен одновременно совпадать на сервере, в
URI, UFW и firewall провайдера. Не отключайте Salamander/Obfuscation для профиля
этого проекта — сервер ожидает тот же секрет, и одностороннее отключение
разорвёт подключение.

## Операционные сценарии

### Проверка

```bash
sudo ./status.sh
sudo docker compose logs --tail 100 hysteria2
sudo ss -lunp | grep ':443'
sudo ufw status
```

Статус контейнера и локальный listener ещё не доказывают прохождение UDP через
фаервол провайдера — окончательная проверка выполняется клиентом из внешней
сети.

### Повторный deploy и обновление проекта

```bash
git pull
sudo ./backup.sh /защищённый/путь/hysteria2-backup.tar.gz
sudo ./deploy.sh
sudo ./status.sh
```

Повторный deploy сохраняет серверные секреты и клиентов. Он не обновляет
Hysteria, пока вы явно не измените одновременно релиз и SHA в `versions.conf`,
не проверите upstream tag и не прогоните тесты.

#### Зачем фиксируются и релиз, и commit

`HYSTERIA_RELEASE` — понятное человеку имя upstream-тега, например
`app/v2.12.2`. `HYSTERIA_COMMIT` — точный 40-символьный Git SHA исходного кода.
Один тег теоретически можно переместить на другой commit; один SHA не объясняет,
какой релиз был выбран. Пара значений решает обе задачи.

Во время deploy скрипт самостоятельно получает SHA тега с официального
репозитория и требует точного совпадения с `versions.conf`. Затем Dockerfile
checkout'ит именно этот SHA. Если upstream выпустит новую версию, обычные
`git pull` и `sudo ./deploy.sh` продолжат использовать проверенную старую
версию. Это защита от неожиданного обновления, а не автоматический updater.

#### Как обновить сервер Hysteria

Пример ниже использует условную новую версию `app/vX.Y.Z`; не копируйте это
значение буквально.

1. Прочитайте release notes в официальных
   [Hysteria Releases](https://github.com/HyNetworks/hysteria/releases) и
   проверьте изменения конфигурации и совместимости клиентов.
2. Получите SHA нового тега:

   ```bash
   git ls-remote https://github.com/HyNetworks/hysteria.git \
     'refs/tags/app/vX.Y.Z^{}'
   ```

   Если тег lightweight и команда ничего не вернула:

   ```bash
   git ls-remote https://github.com/HyNetworks/hysteria.git \
     'refs/tags/app/vX.Y.Z'
   ```

3. В отдельной ветке измените **обе** строки `versions.conf`:

   ```text
   HYSTERIA_RELEASE=app/vX.Y.Z
   HYSTERIA_COMMIT=<полный 40-символьный SHA из предыдущей команды>
   ```

4. Проверьте diff, прогоните тесты и ShellCheck, затем commit/push только этих
   проверенных изменений. Не добавляйте `state/`, `clients/`, `.env`, backup
   или сгенерированный Compose.
5. На VPS сначала сохраните backup, затем получите проверенный commit проекта и
   выполните deploy:

   ```bash
   git pull --ff-only
   sudo ./backup.sh /защищённый/путь/hysteria2-before-upgrade.tar.gz
   sudo ./deploy.sh
   sudo ./status.sh
   ```

6. Проверьте реальное подключение внешним клиентом. Не удаляйте предыдущий образ
   и backup, пока не закончено тестирование. При проблеме используйте
   `sudo ./rollback.sh`.

Новая версия собирается в новый Docker image tag. Существующие сертификат,
Salamander secret, пользователи и `.hy2` сохраняются; заново сканировать QR
обычно не требуется.

#### Нужно ли обновлять приложение-клиент

Этот репозиторий **не устанавливает и не обновляет** клиентские приложения.
v2RAGE обновляют через App Store, а Hiddify — через официальный канал
распространения. Обновление сервера не означает автоматическую замену клиента,
и для обновления приложения не нужно создавать новый пароль или QR.

Перед серверным обновлением прочитайте требования release notes. Если новая
Hysteria требует более новое клиентское ядро, сначала обновите и проверьте один
клиент, затем сервер. Точное совпадение номеров серверной и клиентской версии
нужно не всегда; решающей является заявленная upstream совместимость.

### Backup и rollback

```bash
sudo ./backup.sh /защищённый/путь/hysteria2-backup.tar.gz
sudo ./rollback.sh
```

Backup содержит все клиентские пароли — храните его зашифрованно вне Git и
проверьте восстановление. `rollback.sh` проверяет предыдущую конфигурацию,
создаёт локальный safety-backup и лишь затем переключает контейнер.

### Docker-кэш

Сборка из исходников увеличивает build cache. Сначала оцените его:

```bash
df -h /
sudo docker system df
```

После успешной сборки можно удалить только неиспользуемый build cache; работающие
контейнеры останутся, но следующие сборки будут дольше:

```bash
sudo docker builder prune -af
```

Не используйте `docker system prune -a` без отдельного аудита: он затрагивает
неиспользуемые образы и ресурсы других проектов.

### Полное удаление проекта

```bash
sudo ./cleanup.sh
```

Команда разрушительна и требует подтверждения hostname. Она удаляет контейнер,
образ, сеть, клиентские файлы, ключи и правило UFW, если проект владеет этим
правилом. Общий Docker build cache не очищается.

## Граница безопасности VPS

Проект защищает контейнер Hysteria и свои секретные файлы. Он **не занимается
полным hardening VPS** и не обещает защиту SSH, ОС, панели провайдера, резервных
копий или других сервисов.

Перед использованием в интернете желательно:

1. Включить облачный firewall: разрешить только нужные `UDP/<порт Hysteria>`,
   SSH с доверенных адресов, если это возможно, и необходимые порты других
   сервисов.
2. Включить UFW с `default deny incoming`; не закрывать SSH, пока не проверен
   второй сеанс.
3. Использовать SSH-ключи, отключить password и keyboard-interactive login,
   запретить прямой root login и ограничить `AllowUsers`.
4. Перед reload выполнить `sudo sshd -t`; проверить вход новым соединением и
   только потом закрывать старое.
5. Установить и настроить Fail2ban на фактический SSH-порт.
6. Включить `unattended-upgrades`, регулярно обновлять ОС и перезагружаться,
   когда новое ядро этого требует.
7. Хранить зашифрованные backup вне VPS и проводить тест восстановления.
8. Подключить мониторинг диска, RAM, контейнера и доступности порта.
9. Защитить аккаунт VPS-провайдера и GitHub с помощью MFA и сохранить recovery
   codes в отдельном защищённом месте.

Пример SSH drop-in приведён только как ориентир: параметры зависят от способа
доступа к конкретной VPS. Ошибка может заблокировать вход.

```text
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
X11Forwarding no
```

## Диагностика

Контейнер не запущен:

```bash
sudo docker compose ps
sudo docker compose logs --tail 200 hysteria2
```

Порт или QR не работают:

```bash
sudo ss -lunp | grep ':443'
sudo ufw status
command -v qrencode
sudo test -s clients/iphone.hy2 && echo 'URI exists'
sudo qrencode -t ANSIUTF8 -r clients/iphone.hy2
```

Перед отправкой диагностического вывода удалите URI, пароли, QR-коды,
сертификатные ключи и содержимое `state/`/`clients/`.

## Тесты

```bash
sudo bash tests/run.sh
sudo bash tests/smoke_image.sh local/hysteria2:v2.12.2
shellcheck -x docker-install.sh deploy.sh add-client.sh remove-client.sh \
  status.sh backup.sh cleanup.sh rollback.sh lib/common.sh tests/*.sh
```

## Лицензия и благодарности

Проект распространяется под MIT License. Идея и часть реализации безопасного
установщика Docker, а также структура некоторых операционных рекомендаций
адаптированы из [`seb0ch/vpn`](https://github.com/seb0ch/vpn). См.
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

Владелец и издатель проекта — **cop30**. Архитектура, реализация, инструменты
развёртывания, тесты и документация проекта разработаны преимущественно
**OpenAI Codex** совместно с cop30, который сформулировал требования,
предоставил инфраструктуру, проверял результаты и проводил практическое
тестирование клиентов и сетей.
