# 1. 🔐 SSH конфигурация

Первым делом проверка
```bash
lsb_release -a #подтверждаем Ubuntu.
whoami #смотрим, под каким пользователем ты сейчас работаешь.
hostname -I #смотрим IP-адреса сервера.
ip -br a #смотрим, на каком порту сейчас слушает SSH.
ss -tulpn | grep ssh #смотрим, на каком порту сейчас слушает SSH.
sudo systemctl status ssh --no-pager
```

## Этап 1. Ставим нужные пакеты

```bash
#Обновляем пакеты
sudo apt update
#Устанвливаем новые пакеты

sudo apt install -y openssh-server auditd audispd-plugins iptables-persistent libpam-google-authenticator qrencode
```

> [!NOTE]
> ### Зачем каждый пакет
> 
> `openssh-server` — SSH-сервер, через него будет вход на jump host.  
> `auditd` — аудит действий пользователей.  
> `audispd-plugins` — плагины для обработки audit-событий.  
> `iptables-persistent` — сохранение firewall-правил после перезагрузки.  
> `libpam-google-authenticator` — PAM-модуль для 2FA.  
> `qrencode` — чтобы в терминале красиво показать QR-код для Google Authenticator.
> 
> Google Authenticator PAM-модуль работает как второй фактор TOTP/HOTP: пользователь вводит обычные данные входа и одноразовый код из приложения; секрет хранится обычно в файле `.google_authenticator` в домашней директории пользователя.

## Этап 2. Делаем бэкап SSH-конфига

```bash
#Делаем бэкап существующего конфига с датой
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%F-%H%M%S)


sudo mkdir -p /root/jumphost-backups
sudo cp -a /etc/ssh /root/jumphost-backups/ssh-backup-$(date +%F-%H%M%S)
```


## Этап 3. Создаём группу `ssh-users`

```bash
#Проверка есть ли группа, если предыдущая команда неуспешна, выполни следующую и выполняется вторая команда
getent group ssh-users || sudo groupadd ssh-users


```

## Этап 4. Создаём тестового пользователя

```bash
#Смотрим есть ли пользователь, если команда неуспешна выполняется вторая создание пользователя с домашним каталогом и + shell bash
id jump-test || sudo useradd -m -s /bin/bash jump-test

#Задать пароль пользолвателю
sudo passwd jump-test

#Добавить пользователя в группу не удаляя из других
sudo usermod -aG ssh-users jump-test

#Проверка нашего нового пользователя
id jump-test
```

## Этап 5. Добавляем текущего пользователя в `ssh-users`

```bash
#
whoami

#Добавляем нашего пользователя в группу которой будет разрешен ssh
sudo usermod -aG ssh-users dop2
```

## Этап 6. Создаём отдельный SSH-конфиг для jump host

```bash
#Создаем файл с конфигом
sudo nano /etc/ssh/sshd_config.d/99-jumphost.conf

#Далее вводим наш конфиг

# =========== START =============
# Jump host SSH hardening

Port 2222

PermitRootLogin no

AllowGroups ssh-users

PubkeyAuthentication yes
PasswordAuthentication yes
PermitEmptyPasswords no

AllowTcpForwarding yes
GatewayPorts no
PermitOpen 192.168.0.*:*

X11Forwarding no

ClientAliveInterval 600
ClientAliveCountMax 2

UsePAM yes
KbdInteractiveAuthentication no
# =========== END =============


```

> [!NOTE]
> ## Разбор этого конфига
> 
> SSH будет слушать порт `2222`, а не стандартный `22`.
> ```
> Port 2222
> ```
> 
> Запрещает вход по SSH под `root`. В OpenSSH значение `no` полностью запрещает root-login.
> ```
> PermitRootLogin no
> ```
> 
> Разрешает SSH-вход только пользователям, которые входят в группу `ssh-users`.
> ```
> AllowGroups ssh-users
> ```
> 
> Пока оставляем пароль включённым, чтобы спокойно протестировать. Потом, когда всё заработает с ключами и 2FA, можно будет ужесточить.
> ```
> PubkeyAuthentication yes
> PasswordAuthentication yes
> ```
> 
> Разрешает SSH port forwarding. Это нужно для jump host, чтобы через него ходить к приватным сервисам. В OpenSSH `AllowTcpForwarding` управляет TCP-forwarding и может разрешать или запрещать его.
> ```
> AllowTcpForwarding yes
> ```
> 
> Запрещает открывать проброшенные порты наружу на всех интерфейсах jump host. Это безопаснее.
> ```
> GatewayPorts no
> ```
> 
> Идея: разрешать проброс только к приватной сети `192.168.0.0/24`.
> 
> Но тут важный момент: `PermitOpen` в OpenSSH принимает конкретные `host:port` или шаблоны, а не полноценный CIDR как firewall. Поэтому позже мы дополнительно ограничим это через `iptables`, потому что в задании прямо требуется разрешить форвард портов только в приватную сеть.
> ```
> PermitOpen 192.168.0.*:*
> ```
> 
> Запрещает X11 forwarding. Это нужно, потому что X11 forwarding увеличивает поверхность атаки. OpenSSH manpage отдельно предупреждает про риски X11 forwarding.
> ```
> X11Forwarding no
> ```
> 
> `600` секунд = 10 минут.  
> Сервер будет проверять, жив ли клиент. Если клиент не отвечает 2 раза, сессия будет отключена. `ClientAliveInterval` и `ClientAliveCountMax` именно для этого и используются.
> ```
> ClientAliveInterval 600
> ClientAliveCountMax 2
> ```
> 
> Пока 2FA не включаем. На этапе 2FA поменяем `KbdInteractiveAuthentication` на `yes`. В новых OpenSSH `ChallengeResponseAuthentication` считается устаревшим alias для `KbdInteractiveAuthentication`, поэтому лучше использовать современное имя.
> ```
> UsePAM yes
> KbdInteractiveAuthentication no
> ```

## Этап 7. Проверяем SSH-конфиг до перезапуска

```bash
#Если команда ничего не вывела — это хорошо. Значит синтаксис правильный.
sudo sshd -t

#Смотрим итоговую конфигурацию
sudo sshd -T | grep -E 'port|permitrootlogin|allowgroups|allowtcpforwarding|x11forwarding|clientalive|kbdinteractiveauthentication|passwordauthentication|usepam'
```

## Этап 8. Перезапускаем SSH

```bash
#Перезапускаем сервис ssh
sudo systemctl restart ssh

#Смотрим статус сервиса ssh
sudo systemctl status ssh --no-pager

#Смотрим какой порт слушает SSH
ss -tulpn | grep ssh
```

## Этап 9. SSH все еще слушает 22 порт. Разбор полетов и ошибок


```bash
#Проверяем какие порты слущает ssh
sudo ss -tulpn | grep ssh

#Так же можно проверить прям указав куонкретный порт и какой процесс его слушает
sudo ss -tulpn | grep -E ':22|:2222'

#Проверим что ssh видит наш конфиг который мы сделали
sudo sshd -T | grep -E '^port |^permitrootlogin|^allowgroups|^allowtcpforwarding|^x11forwarding|^clientalive'

#Проверяем где вообще указан порт
sudo grep -RniE '^[[:space:]]*Port|^[[:space:]]*Include' /etc/ssh/sshd_config 
/etc/ssh/sshd_config.d/ 2>/dev/null
#Разбор команды
grep — ищем текст 
-R — recursive, искать внутри папок 
-n — показать номер строки 
-i — не учитывать регистр букв 
-E — использовать расширенное регулярное выражение 
'Port|Include' — ищем строки с Port или Include 
/etc/ssh/... — где ищем 
2>/dev/null — спрятать ошибки доступа или отсутствующих файлов

#Смотрим выводы чтобы разобраться в проблеме
#1. Смотрим статус ssh сервиса (должен быть active) и (--no-pager — не открывать вывод в просмотрщике)
systemctl status ssh.socket --no-pager
#2. Смотрим socket для ssh
systemctl cat ssh.socket
#3. Смотрим порт из нашего конфига
sudo sshd -T | grep '^port '
#4. Смотрим по словам Port и Include файлы в папке /etc/ssh/sshd_config и в папке /etc/ssh/sshd_config.d/
sudo grep -RniE '^[[:space:]]*Port|^[[:space:]]*Include' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/ 2>/dev/null
#5. Просмотр вывода нашего конфига
sudo sshd -T | grep -E '^port |^permitrootlogin|^allowgroups|^allowtcpforwarding|^x11forwarding|^clientalive'
```

### 1. Куда смотреть в итоговом выводе в нашем случае

#### Место №1 — `ssh.socket` активен

Ты выполнил:
```bash
systemctl status ssh.socket --no-pager
```

И получил:
```bash
● ssh.socket - OpenBSD Secure Shell server socket
     Loaded: loaded (/usr/lib/systemd/system/ssh.socket; enabled; preset: enabled)
     Active: active (running) since Wed 2026-07-08 11:58:40 UTC; 2h 11min ago
```

Смотри сюда:
```bash
Active: active (running)
```

Это означает:
> `ssh.socket` включён и работает.

Теоретически:  
Обычно мы думаем, что порт слушает сам `ssh.service`. Но в новых Ubuntu может быть включён механизм **socket activation**. Это когда systemd заранее открывает порт, а потом запускает сервис, когда приходит подключение.

Официально `systemd.socket` — это unit-файл systemd, который описывает IPC или сетевой socket, контролируемый systemd.

#### Место №2.  Самое важное место — порт `22`

В твоём выводе:
```bash
Listen: 0.0.0.0:22 (Stream)
        [::]:22 (Stream)
```

Вот это главное место.

Смотреть сюда:
```bash
0.0.0.0:22
[::]:22
```

Расшифровка:
```bash
0.0.0.0:22 # слушать SSH на всех IPv4-адресах сервера, порт 22
[::]:22    # слушать SSH на всех IPv6-адресах сервера, порт 22
```
То есть сейчас порт слушает **не sshd напрямую**, а `ssh.socket`.

#### Место 3. А SSH-конфиг у тебя правильный

Ты выполнил:

```bash
sudo sshd -T | grep '^port '
```

И получил:
```bash
port 2222
```

Смотреть сюда:
```bash
port 2222
```

Это значит:

> Сам SSH daemon, если читать его конфиг, уже хочет работать на `2222`.

Команда `sshd -T` показывает итоговую конфигурацию OpenSSH после применения всех конфигов. У тебя там всё правильно.

#### Место 4. Файл `99-jumphost.conf` тоже подключился

Ты выполнил:
```bash
sudo grep -RniE '^[[:space:]]*Port|^[[:space:]]*Include' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/ 2>/dev/null
```

И получил:
```bash
/etc/ssh/sshd_config:24:Include /etc/ssh/sshd_config.d/*.conf
/etc/ssh/sshd_config.d/99-jumphost.conf:3:Port 2222
```

Смотреть сюда:
```bash
Include /etc/ssh/sshd_config.d/*.conf
```

Это значит:
> Главный SSH-конфиг подключает дополнительные файлы из `/etc/ssh/sshd_config.d/`.

И сюда:
```bash
/etc/ssh/sshd_config.d/99-jumphost.conf:3:Port 2222
```

Это значит:
> Наш файл `99-jumphost.conf` существует, читается, и в нём на 3-й строке указан `Port 2222`.

В Ubuntu конфиг OpenSSH может подключать дополнительные файлы через `Include`, а Ubuntu-документация по OpenSSH прямо отправляет к `sshd_config(5)` для описания директив.

#### Место 5. Почему тогда порт всё равно 22?

Потому что есть два разных уровня:
```
Уровень 1: sshd_config
Говорит самому SSH-серверу: "используй порт 2222".

Уровень 2: ssh.socket
Говорит systemd: "открой порт 22 и жди подключения".
```

Сейчас у тебя конфликт:
```
sshd_config говорит: port 2222
ssh.socket говорит: ListenStream=0.0.0.0:22
```
И фактически порт слушает `ssh.socket`.

#### Место 6. Ещё одно важное место — `systemctl cat ssh.socket`

Ты выполнил:
```bash
systemctl cat ssh.socket
```

И получил:
```bash
[Socket]
ListenStream=0.0.0.0:22
ListenStream=[::]:22
BindIPv6Only=ipv6-only
Accept=no
FreeBind=yes
```

Смотреть сюда:
```bash
ListenStream=0.0.0.0:22
ListenStream=[::]:22
```

Вот это прям причина проблемы.

Теория:
```bash
ListenStream=
```

Это параметр socket-unit в systemd. Он говорит systemd:
> “Открой TCP-порт и слушай подключения”.

То есть `ssh.socket` не читает `/etc/ssh/sshd_config`.  
У него свой отдельный unit-файл.

#### 7. Что такое `Triggers: ssh.service`

В выводе было:
```
Triggers: ● ssh.service
```

Это значит:
> Когда приходит подключение на порт, который слушает `ssh.socket`, systemd запускает или активирует `ssh.service`.

Простая аналогия:
```
ssh.socket  — охранник у двери, который слушает звонок
ssh.service — сам SSH-сервер, которого зовут, когда кто-то пришёл
```

Сейчас охранник стоит у двери `22`, хотя мы уже сказали SSH-серверу использовать дверь `2222`.

### 2. Действия по исправлению 

Нам надо привести оба уровня к одному порту:
```bash
sshd_config → 2222
ssh.socket  → 2222
```

`sshd_config` у тебя уже правильный.  
Осталось поправить `ssh.socket`.

Важно: мы **не будем редактировать** файл:
```bash
/usr/lib/systemd/system/ssh.socket
```

Почему?  
Потому что это системный файл пакета. При обновлении пакета он может быть перезаписан.

Правильный способ — создать override/drop-in через:
```bash
sudo systemctl edit ssh.socket
```

Это создаст пользовательское переопределение в `/etc/systemd/system/...`, а не испортит оригинальный файл.

---
#### Команды для исправления

##### Шаг 1. Открываем override для `ssh.socket`

```bash
sudo systemctl edit ssh.socket
```

Откроется редактор. Вставь туда:
```bash
[Socket]
ListenStream=
ListenStream=0.0.0.0:2222
ListenStream=[::]:2222
```

Сохрани файл.
Если откроется `nano`:
```bash
Ctrl + O
Enter
Ctrl + X
```

---
##### Теория Очень важная теория про пустой `ListenStream=`

> [!NOTE]
> Вот эта строка нужна обязательно.:
> ```bash
> ListenStream=
> ```
> 
> Она очищает старые значения:
> ```bash
> ListenStream=0.0.0.0:22
> ListenStream=[::]:22
> ```
> 
> Потом мы добавляем новые:
> ```bash
> ListenStream=0.0.0.0:2222
> ListenStream=[::]:2222
> ```
> 
> Без пустой строки systemd может не заменить старые порты, а добавить новые.

----
##### Шаг 2. Перечитываем systemd

После изменения unit-файлов нужно сказать systemd:

> “Перечитай конфиги”.
```bash
sudo systemctl daemon-reload
```

Разбор:
```bash
sudo            — с правами администратора
systemctl       — управление systemd
daemon-reload   — перечитать unit-файлы systemd
```

---
##### Шаг 3. Перезапускаем socket и SSH

Внимание: **не закрывай текущую сессию**.

```bash
sudo systemctl restart ssh.socket
sudo systemctl restart ssh.service
```

Что происходит:

```bash
restart ssh.socket  — systemd заново откроет socket, уже на 2222
restart ssh.service — SSH-сервис перечитает конфиг
```

---
##### Шаг 4. Проверяем

Выполни:
```bash
systemctl status ssh.socket --no-pager
```

Теперь мы хотим увидеть:
```bash
Listen: 0.0.0.0:2222 (Stream)
        [::]:2222 (Stream)
```

Смотреть надо именно сюда:
```bash
Listen:
```

Потом:
```bash
sudo ss -tulpn | grep -E ':22|:2222'
```

Ожидаем что-то такое:
```bash
tcp LISTEN ... 0.0.0.0:2222 ...
tcp LISTEN ... [::]:2222 ...
```

Если порт `22` исчез, а `2222` появился — отлично.

----
##### Шаг 5. Проверяем итоговые конфиги

```bash
sudo sshd -T | grep -E '^port |^permitrootlogin|^allowgroups|^allowtcpforwarding|^x11forwarding|^clientalive'
```

Ожидаем:

```bash
dop2@dop2:~$ sudo sshd -T | grep -E '^port |^permitrootlogin|^allowgroups|^allowtcpforwarding|^x11forwarding|^clientalive'
port 2222
clientaliveinterval 600
clientalivecountmax 2
permitrootlogin no
x11forwarding no
allowtcpforwarding yes
allowgroups ssh-users
```

И:
```bash
systemctl cat ssh.socket
```

Там должно быть видно override примерно такого вида:

```bash
dop2@dop2:~$ systemctl cat ssh.socket
# /usr/lib/systemd/system/ssh.socket
[Unit]
Description=OpenBSD Secure Shell server socket
Before=sockets.target ssh.service
ConditionPathExists=!/etc/ssh/sshd_not_to_be_run

[Socket]
ListenStream=0.0.0.0:22
ListenStream=[::]:22
BindIPv6Only=ipv6-only
Accept=no
FreeBind=yes

[Install]
WantedBy=sockets.target
RequiredBy=ssh.service

# /run/systemd/generator/ssh.socket.d/addresses.conf
# Automatically generated by sshd-socket-generator

[Socket]
ListenStream=
ListenStream=0.0.0.0:2222
ListenStream=[::]:2222
dop2@dop2:~$
```

Смотреть сюда:
```bash
/etc/systemd/system/ssh.socket.d/override.conf
```

Это значит:
> Мы не трогали системный файл в `/usr/lib`, а сделали правильное переопределение в `/etc`.

----
##### Шаг 6. Команды проверки одним блоком

Выполняй по очереди, не закрывая терминал:

```bash
sudo systemctl edit ssh.socket
```

Вставить:
```bash
[Socket]
ListenStream=
ListenStream=0.0.0.0:2222
ListenStream=[::]:2222
```

Потом:
```bash
sudo systemctl daemon-reload
sudo systemctl restart ssh.socket
sudo systemctl restart ssh.service

systemctl status ssh.socket --no-pager
sudo ss -tulpn | grep -E ':22|:2222'
sudo sshd -T | grep -E '^port |^permitrootlogin|^allowgroups|^allowtcpforwarding|^x11forwarding|^clientalive'
systemctl cat ssh.socket
```



### 3. Проверка после исправления

#### Шаг 1. Главное место в `systemctl status ssh.socket`

Ты получил:
```
Listen: 0.0.0.0:2222 (Stream)
        [::]:2222 (Stream)
```

Смотри именно сюда:
```
0.0.0.0:2222
[::]:2222
```

Это значит:
```
0.0.0.0:2222 — SSH слушает порт 2222 на всех IPv4-адресах сервера
[::]:2222    — SSH слушает порт 2222 на всех IPv6-адресах сервера
```

То есть теперь `ssh.socket` слушает **не 22**, а **2222**.

---
#### Шаг 2. Главное место в `ss`

Ты получила:
```
tcp LISTEN 0 4096 0.0.0.0:2222 0.0.0.0:* users:(("sshd",pid=4051,fd=3),("systemd",pid=1,fd=90))
tcp LISTEN 0 4096 [::]:2222    [::]:*    users:(("sshd",pid=4051,fd=4),("systemd",pid=1,fd=91))
```

Смотреть сюда:
```
LISTEN
0.0.0.0:2222
[::]:2222
users:(("sshd"...),("systemd"...))
```

Разбор:
```
LISTEN — порт открыт и ждёт подключения
0.0.0.0:2222 — слушает порт 2222 на IPv4
[::]:2222 — слушает порт 2222 на IPv6
sshd — SSH-сервер участвует в прослушивании
systemd — systemd socket activation тоже участвует
```
И очень важно: в твоём выводе **нет `:22`**.
Значит старый порт больше не слушается.

---
#### Шаг 3. Почему в `systemctl cat ssh.socket` всё ещё видно `22`

Вот это может сбивать с толку:
```bash
# /usr/lib/systemd/system/ssh.socket

[Socket]
ListenStream=0.0.0.0:22
ListenStream=[::]:22
```
Смотри: это **оригинальный системный unit-файл**.

Но ниже у тебя есть:
```bash
# /run/systemd/generator/ssh.socket.d/addresses.conf
# Automatically generated by sshd-socket-generator

[Socket]
ListenStream=
ListenStream=0.0.0.0:2222
ListenStream=[::]:2222
```

Вот сюда надо смотреть:
```bash
ListenStream=
ListenStream=0.0.0.0:2222
ListenStream=[::]:2222
```

Теория:

`systemctl cat ssh.socket` показывает **все слои конфигурации**:
```bash
1. базовый unit из /usr/lib/systemd/system/ssh.socket
2. дополнительные drop-in файлы
3. автоматические generated-файлы
```

У тебя базовый файл говорит:
```txt
слушай 22
```

А generated drop-in ниже говорит:
```txt
очисти старые ListenStream
слушай 2222
```

Вот эта строка:
```bash
ListenStream=
```

означает:
> “Сбросить старые значения ListenStream”.

После неё systemd применяет:
```
ListenStream=0.0.0.0:2222
ListenStream=[::]:2222
```

Поэтому фактически работает именно `2222`.

#### Шаг 4. Почему появился `/run/systemd/generator/...`, а не `/etc/systemd/system/...`

Ты получила:
```
# /run/systemd/generator/ssh.socket.d/addresses.conf
# Automatically generated by sshd-socket-generator
```

Это значит:
> systemd сам сгенерировал drop-in для `ssh.socket` на основе SSH-настроек.

То есть у тебя не ручной override в `/etc/systemd/system/ssh.socket.d/override.conf`, а автоматический generated override.

Это нормально. Главное — фактическая проверка через:
```
systemctl status ssh.socket --no-pager
sudo ss -tulpn | grep -E ':22|:2222'
```

Они показывают, что реально слушается `2222`.

---
#### Шаг 5. Маленькая схема, что сейчас происходит

```
/etc/ssh/sshd_config.d/99-jumphost.conf
        ↓
говорит OpenSSH: Port 2222

sshd-socket-generator
        ↓
создаёт /run/systemd/generator/ssh.socket.d/addresses.conf

ssh.socket
        ↓
слушает 0.0.0.0:2222 и [::]:2222

ssh.service / sshd
        ↓
принимает SSH-подключения
```

То есть теперь цепочка правильная.

---
#### Шаг 6. Теперь обязательно проверяем вход по SSH

Сначала на сервере проверь, что твой пользователь `dop2` в группе `ssh-users`:

```
id dop2
```

Смотреть надо сюда
```
groups=...,ssh-users
```

Если `ssh-users` есть — хорошо.

Если нет, добавь:
```
sudo usermod -aG ssh-users dop2
```

После добавления группы для текущей сессии это может не примениться сразу, но для нового SSH-входа должно сработать.

---
#### Шаг 7. Проверка подключения с твоего компьютера

Открой **новое окно терминала** на своём компьютере. Старое окно с сервером не закрывай.

Подключись так:

```
ssh -p 2222 dop2@192.168.31.179
```

Почему именно этот IP?  
В твоём прошлом выводе был адрес:

```
192.168.31.179
```

Это адрес интерфейса `enp0s3`.

Разбор команды:

```
ssh — SSH-клиент
-p 2222 — подключаться не на стандартный порт 22, а на 2222
dop2 — имя пользователя на сервере
192.168.31.179 — IP-адрес сервера
```

Если ты подключаешься из другой VM-сети, возможно нужен второй IP:

```
ssh -p 2222 dop2@192.168.203.4
```

---

#### Шаг 8. Проверяем, что порт 22 больше не работает

После того как `2222` заработает, можно проверить старый порт:
```
ssh -p 22 dop2@192.168.31.179
```

Ожидаемый результат:
```
Connection refused
```

или:
```
Connection timed out
```

Это нормально: порт 22 больше не слушается.


----
# 2. 🔗 Настройка SSH туннелирования
Что нужно сделать:
- Включить port forwarding в SSH конфиге
- Запретить X11 forwarding
- Настроить `ClientAliveInterval` на 10 минут
- Настроить `ClientAliveCountMax` для автоматического отключения

## 1. Небольшая теоретическая часть этого этапа
### Цель этого этапа

Мы должны научиться делать так:
```
Твой компьютер
      ↓ SSH на порт 2222
Jump host
      ↓ доступ во внутреннюю/приватную сеть
Приватный сервис
```
То есть снаружи приватный сервис напрямую недоступен, но мы можем попасть к нему **через jump host**.

### 1. Что такое SSH-туннель простыми словами

SSH-туннель — это когда мы используем SSH не только для входа в терминал, но и как **защищённый канал для другого трафика**.

Например, у нас есть сервис внутри сети:
```
192.168.203.10:80
```

С твоего компьютера он недоступен.

Но jump host видит эту сеть. Тогда мы можем сделать:
```
127.0.0.1:18080 на твоём компьютере
        ↓
SSH-туннель
        ↓
192.168.203.10:80 изнутри jump host
```

После этого ты открываешь у себя:
```
http://127.0.0.1:18080
```

А фактически попадаешь на:
```
http://192.168.203.10:80
```

---
### 2. Виды SSH-туннелей

Нам сейчас важен **Local Port Forwarding**.

Local forwarding: `-L`
Формат:
```
ssh -L ЛОКАЛЬНЫЙ_ПОРТ:ЦЕЛЕВОЙ_ХОСТ:ЦЕЛЕВОЙ_ПОРТ user@jump-host
```

Более безопасный вариант:
```
ssh -L 127.0.0.1:ЛОКАЛЬНЫЙ_ПОРТ:ЦЕЛЕВОЙ_ХОСТ:ЦЕЛЕВОЙ_ПОРТ user@jump-host
```

Почему добавляем `127.0.0.1`?
Потому что так туннель будет доступен **только на твоём компьютере**, а не всей локальной сети.

---
### 3. Разбор команды SSH-туннеля

Пример:
```
ssh -p 2222 -N -L 127.0.0.1:18080:127.0.0.1:9000 dop2@192.168.31.179
```

Разбираем по частям:
```
ssh — SSH-клиент
-p 2222 — подключаться к jump host на порт 2222
-N — не открывать shell, только держать туннель
-L — создать local port forwarding
127.0.0.1:18080 — порт на твоём компьютере
127.0.0.1:9000 — куда идти со стороны jump host
dop2 — пользователь на jump host
192.168.31.179 — IP jump host
```

Самая важная часть:
```
-L 127.0.0.1:18080:127.0.0.1:9000
```

Она читается так:
> “Открой на моём компьютере порт `18080`, а весь трафик отправляй через SSH на `127.0.0.1:9000` со стороны jump host.”

Очень важная теория:
```
ЦЕЛЕВОЙ_ХОСТ после -L определяется не с твоего компьютера, а со стороны jump host.
```

То есть если ты пишешь:
```
-L 127.0.0.1:18080:192.168.203.10:80
```

то `192.168.203.10:80` должен быть доступен **с jump host**, а не обязательно с твоего компьютера.

---
## 2. Практические шаги к реализации

### Шаг 1. Сначала сделаем учебную проверку без приватного сервера

Чтобы не зависеть от отдельной приватной машины, мы сначала поднимем маленький тестовый HTTP-сервис прямо на jump host, но только на `127.0.0.1`.

Так мы проверим сам механизм туннеля.
На jump host выполни:
```
mkdir -p ~/tunnel-test
echo "SSH tunnel works" > ~/tunnel-test/index.html
python3 -m http.server 9000 --bind 127.0.0.1 --directory ~/tunnel-test
```
Что делает каждая команда:

Создаёт папку `tunnel-test` в домашней директории.
```bash
#Создаем папку в домашней директории
mkdir -p ~/tunnel-test

#Создаёт файл index.html с текстом "SSH tunnel works"
echo "SSH tunnel works" > ~/tunnel-test/index.html

#Запускает простой HTTP-сервер
python3 -m http.server 9000 --bind 127.0.0.1 --directory ~/tunnel-test
```

Разбор:
```bash
python3 # интерпретатор Python 
-m http.server # запустить встроенный модуль HTTP-сервера 
9000 # порт, на котором будет работать сервис 
--bind 127.0.0.1 # слушать только localhost 
--directory ~/tunnel-test # отдавать файлы из этой папки
```

Очень важное место:
```bash
--bind 127.0.0.1
```
Это значит, что сервис доступен только локально на jump host. Снаружи напрямую его открыть нельзя. Это как раз удобно для проверки туннеля.
Этот терминал оставь открытым. Там будет работать тестовый веб-сервер.

### Шаг 2. Проверяем, что сервис работает на jump host

Открой **второй терминал на jump host** или в той же машине после остановки сервера нельзя, поэтому лучше второе окно.

Выполни:
```
curl http://127.0.0.1:9000
```

Ожидаем:
```
SSH tunnel works
```

Если `curl` нет:
```
sudo apt install -y curl
```

![[Pasted image 20260708232020.png]]

### Шаг 3. Теперь создаём SSH-туннель с твоего компьютера

На своём компьютере, не на сервере, выполни:
```
ssh -p 2222 -N -L 127.0.0.1:18080:127.0.0.1:9000 dop2@192.168.31.179
```

Терминал как будто “зависнет”. Это нормально.
Почему?

Потому что ключ:
```bash
#Не открывай shell, просто держи туннель. Пока это окно открыто, туннель работает.
-N 
```


Мы получили ошибки рода:
```
PS C:\Users\skame> ssh -p 2222 -N -L 127.0.0.1:18080:127.0.0.1:9000 dop2@192.168.31.179 dop2@192.168.31.179's password: 
channel 1: open failed: administratively prohibited: open failed 
channel 1: open failed: administratively prohibited: open failed 
channel 1: open failed: administratively prohibited: open failed
```
В след шаге мы поправим это

### Шаг 4. Нахождение ошибок + Исправление ошибок

При проверке снаружи для ручного подключения к jump host у нас появились проблемы. В третьем окне терминала мы получили такие ошибки смотрим ниже: 
```
PS C:\Users\skame> ssh -p 2222 -N -L 127.0.0.1:18080:127.0.0.1:9000 dop2@192.168.31.179 dop2@192.168.31.179's password: 
channel 1: open failed: administratively prohibited: open failed 
channel 1: open failed: administratively prohibited: open failed 
channel 1: open failed: administratively prohibited: open failed
```

 **Где ошибка?**

Вот главное место:
```bash
channel 1: open failed: administratively prohibited: open failed
```

Смотреть надо на:
```
administratively prohibited
```
Это значит:
> SSH-сервер административно запретил открыть канал port forwarding.


То есть вход по SSH прошёл, но когда SSH попытался пробросить соединение к:
```
127.0.0.1:9000
```

сервер сказал:
```
Нельзя. Такой forwarding запрещён настройками.
```

---
 Почему так произошло?

Скорее всего, у нас в SSH-конфиге стоит ограничение `PermitOpen`.
Например, что-то такое:
```
PermitOpen 192.168.0.*:*
```

А ты сейчас пробрасываешь не в `192.168...`, а сюда:
```
127.0.0.1:9000
```

Поэтому SSH и запрещает.
Теория: `AllowTcpForwarding` включает или выключает TCP forwarding в целом; у него есть режимы `yes/all`, `no`, `local`, `remote` . А `PermitOpen` уже ограничивает, **к каким destination host:port разрешено открывать TCP forwarding**; по документации OpenSSH там можно указывать `host:port`, `IPv4_addr:port`, `[IPv6_addr]:port`, а `*` можно использовать как wildcard для host или port

---
### 4.1 Сначала проверим, что реально стоит в конфиге. 

На jump host выполним:
```bash
#Команда для вывовда определенных строк нащего конфига для ssh
sudo sshd -T | grep -E '^allowtcpforwarding|^permitopen|^disableforwarding|^gatewayports'

#Вывод. Смотреть будем на строки:
gatewayports no
allowtcpforwarding yes
disableforwarding no
permitopen 192.168.0.*:*
```

Также выполним:
```bash
#Поиск строк в папке /etc/ssh/sshd_config и etc/ssh/sshd_config.d/
sudo grep -RniE 'AllowTcpForwarding|PermitOpen|DisableForwarding|GatewayPorts|Match' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/ 2>/dev/null

#Вывод команды
/etc/ssh/sshd_config:111:#AllowTcpForwarding yes
/etc/ssh/sshd_config:112:#GatewayPorts no
/etc/ssh/sshd_config:141:#Match User anoncvs
/etc/ssh/sshd_config:143:#      AllowTcpForwarding no
/etc/ssh/sshd_config.d/99-jumphost.conf:13:AllowTcpForwarding yes
/etc/ssh/sshd_config.d/99-jumphost.conf:14:GatewayPorts no
/etc/ssh/sshd_config.d/99-jumphost.conf:15:PermitOpen 192.168.0.*:*
```

---
#### **Быстрое учебное исправление для нашего теста**

Для учебной проверки туннеля нам нужно временно разрешить проброс к:
```
127.0.0.1:9000
```

Открой SSH-конфиг:
```
sudo nano /etc/ssh/sshd_config.d/99-jumphost.conf
```

Найди строку `PermitOpen`. Если она такая:
```
PermitOpen 192.168.0.*:*
```

или похожая, замени её на:
```
PermitOpen 127.0.0.1:9000 192.168.*:*
```

Если строки `PermitOpen` нет, добавим:
```
PermitOpen 127.0.0.1:9000 192.168.*:*
```

---
 #### **Почему именно так**
 
```
PermitOpen 127.0.0.1:9000 192.168.*:*
```

Разбор:
```
127.0.0.1:9000 — разрешаем наш учебный тестовый сервис на jump host
192.168.*:* — разрешаем приватные адреса 192.168.x.x на любые порты
```

Важно: `PermitOpen` не понимает CIDR как `192.168.0.0/24` в том же смысле, как firewall. Для строгого ограничения по CIDR мы позже будем использовать `iptables`. В SSH-конфиге сейчас делаем рабочее ограничение для лабораторной проверки.

Смотреть особенно на:

```
PermitOpen
```

Если там есть `PermitOpen 192.168...`, это и есть причина.

----
#### **Проверяем конфиг перед перезапуском**

```bash
sudo sshd -t
```

Смотреть:
```txt
если вывода нет — всё хорошо
если есть ошибка — не перезапускаем SSH
```

---
#### **Перезапускаем SSH**

```bash
#Перезапускаем сервис ssh
sudo systemctl restart ssh

#Если используется socket то стоит еще и его перезапустить
sudo systemctl restart ssh.socket
sudo systemctl restart ssh
```

---
#### Проверяем, что SSH видит новый `PermitOpen`

```bash
#Смотрим определенные строки нашего конфига
sudo sshd -T | grep -E '^allowtcpforwarding|^permitopen|^disableforwarding|^gatewayports'

#Вывод
gatewayports no
allowtcpforwarding yes
disableforwarding no
permitopen 127.0.0.1:9000 192.168.*:*
```

Именно это разрешает наш тестовый туннель.:
```
permitopen 127.0.0.1:9000
```


### Шаг 5. Повторная попытка запуска тунеля

Если после пароля терминал просто “молчит” и не возвращает prompt — это хорошо. Значит туннель держится открытым. В PowerShell:
```bash
#Запуск ручного тунеля. После пароля ничего не должно быть
ssh -p 2222 -N -L 127.0.0.1:18080:127.0.0.1:9000 dop2@192.168.31.179
```

Проверяем что наш сервис запущен и все ок:
```bash
dop2@dop2:~$ python3 -m http.server 9000 --bind 127.0.0.1 --directory ~/tunnel-test
Serving HTTP on 127.0.0.1 port 9000 (http://127.0.0.1:9000/) ...
127.0.0.1 - - [08/Jul/2026 21:22:16] "GET / HTTP/1.1" 200 -
```

В другом терминале делаем вот так:
```bash
#Вводим в терминал
PS C:\Users\skame> curl.exe http://127.0.0.1:18080
#Вывод должен быть вот таким
SSH tunnel works
```


# 3. 📊 Логирование аудита

По заданию нам нужно:
```
1. Установить auditd;
2. Настроить auditd для логирования всех команд пользователей;
3. Создать скрипт для отправки алертов о новых SSH подключениях;
4. Настроить запуск скрипта алертов через PAM или rsyslog.
```

Предлагаю делать через **PAM**, потому что это очень понятно: пользователь успешно вошёл по SSH → PAM запускает наш скрипт → скрипт пишет alert в лог.

---
## 1. Теория: что именно будет логировать auditd

Когда пользователь вводит команду:
```
ls -la /etc
```

shell запускает программу `ls`. На уровне ядра это выглядит как системный вызов:
```
execve()
```

Поэтому для “логирования команд” мы будем аудировать именно `execve`. Важно: auditd хорошо видит запуск внешних программ:
```
ls, cat, sudo, nano, curl, ssh, usermod, systemctl
```

Но shell built-in команды могут не попадать как отдельный `execve`, например:
```
cd
export
alias
```

Почему? Потому что `cd` выполняется внутри самого shell, отдельная программа `/usr/bin/cd` обычно не запускается.

То есть честно формулируем так:
> Мы настроим auditd на логирование запуска команд/программ пользователями через `execve`.

----
## 2. Проверяем, установлен ли auditd

На сервере выполним:
```bash
dpkg -l | grep auditd

#Разбор
dpkg -l       # показать установленные пакеты
grep auditd  # оставить только строки, где есть auditd
```

Если ничего не вывело — ставим:
```bash
#Обновить пакеты
sudo apt update
#Установить auditd
sudo apt install -y auditd audispd-plugins
```

---
## 3. Проверяем статус auditd

```bash
#Проверяем статус сервиса auditd
sudo systemctl status auditd --no-pager
```

Смотреть нужно сюда:
```bash
Active: active (running)
```

Если будет так — хорошо:
```bash
Active: active (running)
```

Если нет, и сервис выключен, то запускаем:
```bash
#Проверка статуса сериса
sudo systemctl enable --now auditd

#Разбор
systemctl # управление systemd-сервисами
enable    # включить автозапуск после перезагрузки
--now     # сразу запустить прямо сейчас
auditd    # имя сервиса

```

----
## 4. Проверяем текущее состояние audit

`auditctl` — утилита для настройки kernel audit system: она умеет смотреть статус, загружать и управлять audit-правилами.
```bash
sudo auditctl -s
```

В выводе смотри на такие места:
```bash
enabled 1
backlog 0
lost 0
```

Что это значит:
```bash
enabled 1 — аудит включён
lost 0    — потерянных audit-событий нет
```
Если `lost` не 0 — это плохо, значит auditd не успевал обрабатывать события.

----
## 5. Делаем backup audit-правил

Перед изменениями:
```bash
sudo mkdir -p ~/jumphost-backups/audit
sudo cp -a /etc/audit ~/jumphost-backups/audit/audit-backup-$(date +%F-%H%M%S)

#Разбор команды
mkdir -p # создать папку, не ругаться если уже есть
cp -a    # архивное копирование с сохранением прав и структуры 
$(date +%F-%H%M%S) # добавить дату и время в имя backup

```

## Разбор
```
mkdir -p — создать папку, не ругаться если уже есть
cp -a    — архивное копирование с сохранением прав и структуры
$(date +%F-%H%M%S) — добавить дату и время в имя backup
```

---
## 6. Создаём отдельный файл правил для jump host

Открываем файл:
```bash
sudo nano /etc/audit/rules.d/50-jumphost.rules
```

Вставляем: и сохраняем
```bash
# Jump host audit rules

# Увеличиваем буфер audit-событий
-b 8192

# При ошибках auditd писать предупреждение, но не останавливать систему
-f 1

# Логировать запуск команд пользователями
-a always,exit -F arch=b64 -S execve -F auid>=1000 -F auid!=4294967295 -k user-commands
-a always,exit -F arch=b32 -S execve -F auid>=1000 -F auid!=4294967295 -k user-commands

# Следить за SSH-конфигурацией
-w /etc/ssh/sshd_config -p wa -k ssh-config
-w /etc/ssh/sshd_config.d/ -p wa -k ssh-config

# Следить за sudoers
-w /etc/sudoers -p wa -k sudoers
-w /etc/sudoers.d/ -p wa -k sudoers

# Следить за пользователями и группами
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/gshadow -p wa -k identity
```

---
## 7. Подробный разбор правил

### 7.1 Правило буфера

```bash
-b 8192
```

Это backlog buffer. Простыми словами:

> Сколько audit-событий ядро может держать в очереди, пока auditd их обрабатывает.

Почему ставим `8192`?  
Потому что логирование команд может быть шумным, и маленький буфер может привести к потерянным событиям.

---

### 7.2 Правило реакции на ошибку

```bash
-f 1
```

Для учебного jump host ставим `1`, чтобы система не падала из-за проблем с audit, это failure mode. Простыми словами:
```bash
0 — молча игнорировать проблемы
1 — писать предупреждения
2 — panic/жёсткая реакция
```


---

### 7.3 Главное правило логирования команд

```bash
#Разбираем:
-a always,exit -F arch=b64 -S execve -F auid>=1000 -F auid!=4294967295 -k user-commands

#==========================
#Добавить правило: всегда логировать событие на выходе из syscall.
-a always,exit

#Фильтр по архитектуре: 64-bit.
-F arch=b64

#Логировать системный вызов `execve`, то есть запуск программ.
-S execve

#Логировать обычных пользователей. В Linux обычные пользователи обычно имеют UID от `1000`.
-F auid>=1000

#Исключить события без нормального login UID. Значение `4294967295` часто означает unset loginuid.
-F auid!=4294967295


#Добавить ключ/метку события. 
-k user-commands
#Потом мы сможем искать так:
sudo ausearch -k user-commands

```

---
### 7.4 Почему есть `b64` и `b32`

```bash
#На 64-битной системе могут быть как 64-битные, так и 32-битные syscall-таблицы. Поэтому часто добавляют оба правила.
-a always,exit -F arch=b64 ...
-a always,exit -F arch=b32 ...
```

---
### 7.5 Правило наблюдения за SSH-конфигом

```bash
#Разбор:
-w /etc/ssh/sshd_config -p wa -k ssh-config

#===========================
-w /path # watch, следить за файлом или директорией
-p wa   # permissions/events: write и attribute change
-k      # ключ для поиска

#Дополнительно про -p wa:
#w — запись/изменение файла
#a — изменение атрибутов: права, владелец, timestamps и т.д.
```

То есть:
> Если кто-то поменяет SSH-конфиг, auditd это запишет.

Файл `audit.rules` содержит audit-правила, которые загружаются audit daemon’ом; синтаксис таких правил по сути такой же, как у команд `auditctl`, только без написания самого `auditctl` в начале строки.

---
## 8. Загружаем правила

На Ubuntu/Debian правила из `/etc/audit/rules.d/` обычно собираются через `augenrules`.

Выполним, если команда ничего плохого не вывела — хорошо:
```bash
sudo augenrules --load
```

Потом проверяем список активных правил:
```bash
#Команда для вывода списка активных правил:
sudo auditctl -l

#Смотреть надо, чтобы были строки с:
user-commands
ssh-config
sudoers
identity
```

---
## 9. Перезапускаем auditd

На некоторых системах auditd не любят обычный `restart`, но попробуем стандартно:
```bash
sudo systemctl restart auditd
```

Если будет сообщение, что restart запрещён или не сработал, тогда выполним:
```bash
sudo service auditd restart
```

Потом:
```bash
sudo systemctl status auditd --no-pager
```

Смотреть:
```
Active: active (running)
```

----
## 10. Делаем тестовые команды

Теперь выполни под обычным пользователем `dop2`:
```bash
whoami
ls /etc/ssh
sudo -l
```

Зачем:
```bash
whoami    # простая команда пользователя
ls        # команда просмотра файлов
sudo -l   # проверка sudo-доступа, важно для аудита
```

---
## 11. Ищем события команд

Теперь ищем audit-события:
```bash
sudo ausearch -k user-commands -i | tail -n 80

#Разбор
ausearch          — поиск по audit-логам
-k user-commands  — искать события с ключом user-commands
-i                — интерпретировать числовые значения в человекочитаемый вид
tail -n 80        — показать последние 80 строк
```


Смотреть надо на места:
```bash
type=EXECVE
```

и:
```bash
a0="whoami"
a0="ls"
a0="sudo"
```

Примерно ты можешь увидеть:
```
type=EXECVE msg=audit(...): argc=1 a0="whoami"
```

Это значит:
> auditd зафиксировал запуск команды `whoami`.

----
## 12. Удобный отчёт по выполненным программам

Можно сделать сводку:
```bash

sudo aureport -x --summary

#Разбор
aureport    — отчёты по audit-логам
-x          — executable report, отчёт по исполняемым файлам
--summary   — сводка
```

Смотреть надо на список исполняемых файлов:
```
/usr/bin/sudo
/usr/bin/ls
/usr/bin/whoami
```

---
## 13. Проверяем аудит изменения SSH-конфига

Осторожно: не будем ломать конфиг. Просто изменим timestamp файла через `touch`.
```bash
sudo touch /etc/ssh/sshd_config.d/99-jumphost.conf
```

Теперь ищем:
```bash
sudo ausearch -k ssh-config -i | tail -n 50
```

Смотреть надо на:
```bash
#На какие строчки смотреть:
name="/etc/ssh/sshd_config.d/99-jumphost.conf"
key="ssh-config"
```

Это значит:
> auditd заметил изменение файла SSH-конфигурации.

---
## 14. Проверка части выполненной работы

1 Выполнить по порядку и посмотреть выводы:
```bash
#Проверка статуса auditd
sudo systemctl status auditd --no-pager

sudo auditctl -s
sudo nano /etc/audit/rules.d/50-jumphost.rules
sudo augenrules --load
sudo auditctl -l

#Выводы команд:
#==================== START =================================
dop2@dop2:~$ sudo systemctl status auditd --no-pager
[sudo: authenticate] Password:
● auditd.service - Security Audit Logging Service
     Loaded: loaded (/usr/lib/systemd/system/auditd.service; enabled; preset: enabled)
     Active: active (running) since Mon 2026-07-13 10:50:18 UTC; 1h 22min ago
 Invocation: 2c4a896f70c74348b9378fba942521ac
       Docs: man:auditd(8)
             https://github.com/linux-audit/audit-documentation
    Process: 4147 ExecStart=/usr/sbin/auditd (code=exited, status=0/SUCCESS)
   Main PID: 4148 (auditd)
      Tasks: 2 (limit: 3971)
     Memory: 1.2M (peak: 2M)
        CPU: 30ms
     CGroup: /system.slice/auditd.service
             └─4148 /usr/sbin/auditd

Jul 13 10:50:18 dop2 systemd[1]: Starting auditd.service - Security Audit Logging Service...
Jul 13 10:50:18 dop2 auditd[4148]: No plugins found, not dispatching events
Jul 13 10:50:18 dop2 auditd[4148]: Init complete, auditd 4.1.2 listening for events (startup state enable)
Jul 13 10:50:18 dop2 systemd[1]: Started auditd.service - Security Audit Logging Service.

#============================================================

dop2@dop2:~$ sudo auditctl -s
enabled 1
failure 1
pid 4148
rate_limit 0
backlog_limit 8192
lost 0
backlog 0
backlog_wait_time 60000
backlog_wait_time_actual 0
loginuid_immutable 0 unlocked

#============================================================

dop2@dop2:~$ sudo cat /etc/audit/rules.d/50-jumphost.rules
# Jump host audit rules

# Увеличиваем буфер audit-событий
-b 8192

# При ошибках auditd писать предупреждение, но не останавливать систему
-f 1

# Логировать запуск команд пользователями
-a always,exit -F arch=b64 -S execve -F auid>=1000 -F auid!=4294967295 -k user-commands
-a always,exit -F arch=b32 -S execve -F auid>=1000 -F auid!=4294967295 -k user-commands

# Следить за SSH-конфигурацией
-w /etc/ssh/sshd_config -p wa -k ssh-config
-w /etc/ssh/sshd_config.d/ -p wa -k ssh-config

# Следить за sudoers
-w /etc/sudoers -p wa -k sudoers
-w /etc/sudoers.d/ -p wa -k sudoers

# Следить за пользователями и группами
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/gshadow -p wa -k identity

#============================================================

dop2@dop2:~$ sudo augenrules --load
/usr/sbin/augenrules: No change
No rules
enabled 1
failure 1
pid 4148
rate_limit 0
backlog_limit 8192
lost 0
backlog 4
backlog_wait_time 60000
backlog_wait_time_actual 0
enabled 1
failure 1
pid 4148
rate_limit 0
backlog_limit 8192
lost 0
backlog 4
backlog_wait_time 60000
backlog_wait_time_actual 0
Old style watch rules are slower
Old style watch rules are slower
Old style watch rules are slower
Old style watch rules are slower
Old style watch rules are slower
Old style watch rules are slower
Old style watch rules are slower
Old style watch rules are slower
enabled 1
failure 1
pid 4148
rate_limit 0
backlog_limit 8192
lost 0
backlog 0
backlog_wait_time 60000
backlog_wait_time_actual 0

#============================================================

dop2@dop2:~$ sudo auditctl -l
-a always,exit -F arch=b64 -S execve -F auid>=1000 -F auid!=-1 -F key=user-commands
-a always,exit -F arch=b32 -S execve -F auid>=1000 -F auid!=-1 -F key=user-commands
-w /etc/ssh/sshd_config -p wa -k ssh-config
-w /etc/ssh/sshd_config.d -p wa -k ssh-config
-w /etc/sudoers -p wa -k sudoers
-w /etc/sudoers.d -p wa -k sudoers
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/gshadow -p wa -k identity

#==================== END ===================================
```


Потом идут тесты:
```bash
whoami
ls /etc/ssh
sudo -l
sudo ausearch -k user-commands -i | tail -n 80


#Выводы команд:
# ============================ START ==========================

dop2@dop2:~$ whoami
dop2

#==============================================================

dop2@dop2:~$ ls /etc/ssh
moduli      ssh_config.d        ssh_host_ecdsa_key.pub  ssh_host_ed25519_key.pub  ssh_host_rsa_key.pub  sshd_config                           sshd_config.d
ssh_config  ssh_host_ecdsa_key  ssh_host_ed25519_key    ssh_host_rsa_key          ssh_import_id         sshd_config.backup.2026-07-08-124609

# ==============================================================

dop2@dop2:~$ sudo -l
User dop2 may run the following commands on dop2:
    (ALL : ALL) ALL


#============================================================

dop2@dop2:~$ sudo ausearch -k user-commands -i | tail -n 80
type=CWD msg=audit(07/13/2026 12:16:34.024:1096) : cwd=/home/dop2
type=EXECVE msg=audit(07/13/2026 12:16:34.024:1096) : argc=7 a0=sed a1=-e a2=s/\\/\\x5c/g a3=-e a4=s/;/\\x3b/g a5=-e a6=s/[[:cntrl:]]/⍰/g
type=SYSCALL msg=audit(07/13/2026 12:16:34.024:1096) : arch=x86_64 syscall=execve success=yes exit=0 a0=0x5fa0ff12b0d0 a1=0x5fa0ff11ecf0 a2=0x5fa0ff0e64a0 a3=0x8 items=2 ppid=4979 pid=4981 auid=dop2 uid=dop2 gid=dop2 euid=dop2 suid=dop2 fsuid=dop2 egid=dop2 sgid=dop2 fsgid=dop2 tty=pts0 ses=12 comm=sed exe=/usr/bin/sed subj=unconfined key=user-commands
----
type=PROCTITLE msg=audit(07/13/2026 12:16:44.441:1097) : proctitle=sed -e s/\\/\\x5c/g -e s/;/\\x3b/g -e s/[[:cntrl:]]/⍰/g
type=PATH msg=audit(07/13/2026 12:16:44.441:1097) : item=1 name=/lib64/ld-linux-x86-64.so.2 inode=1730435 dev=08:02 mode=file,755 ouid=root ogid=root rdev=00:00 nametype=NORMAL cap_fp=none cap_fi=none cap_fe=0 cap_fver=0 cap_frootid=0
type=PATH msg=audit(07/13/2026 12:16:44.441:1097) : item=0 name=/usr/bin/sed inode=1705250 dev=08:02 mode=file,755 ouid=root ogid=root rdev=00:00 nametype=NORMAL cap_fp=none cap_fi=none cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(07/13/2026 12:16:44.441:1097) : cwd=/home/dop2
type=EXECVE msg=audit(07/13/2026 12:16:44.441:1097) : argc=7 a0=sed a1=-e a2=s/\\/\\x5c/g a3=-e a4=s/;/\\x3b/g a5=-e a6=s/[[:cntrl:]]/⍰/g
type=SYSCALL msg=audit(07/13/2026 12:16:44.441:1097) : arch=x86_64 syscall=execve success=yes exit=0 a0=0x5fa0ff1285a0 a1=0x5fa0ff11ecf0 a2=0x5fa0ff0e64a0 a3=0x8 items=2 ppid=4984 pid=4986 auid=dop2 uid=dop2 gid=dop2 euid=dop2 suid=dop2 fsuid=dop2 egid=dop2 sgid=dop2 fsgid=dop2 tty=pts0 ses=12 comm=sed exe=/usr/bin/sed subj=unconfined key=user-commands
----
type=PROCTITLE msg=audit(07/13/2026 12:16:44.443:1098) : proctitle=ls --color=auto /etc/ssh
type=PATH msg=audit(07/13/2026 12:16:44.443:1098) : item=1 name=/lib64/ld-linux-x86-64.so.2 inode=1730435 dev=08:02 mode=file,755 ouid=root ogid=root rdev=00:00 nametype=NORMAL cap_fp=none cap_fi=none cap_fe=0 cap_fver=0 cap_frootid=0
type=PATH msg=audit(07/13/2026 12:16:44.443:1098) : item=0 name=/usr/bin/ls inode=1704334 dev=08:02 mode=file,755 ouid=root ogid=root rdev=00:00 nametype=NORMAL cap_fp=none cap_fi=none cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(07/13/2026 12:16:44.443:1098) : cwd=/home/dop2
type=EXECVE msg=audit(07/13/2026 12:16:44.443:1098) : argc=3 a0=ls a1=--color=auto a2=/etc/ssh
type=SYSCALL msg=audit(07/13/2026 12:16:44.443:1098) : arch=x86_64 syscall=execve success=yes exit=0 a0=0x5fa0ff128580 a1=0x5fa0ff1167d0 a2=0x5fa0ff0e64a0 a3=0x31 items=2 ppid=4845 pid=4987 auid=dop2 uid=dop2 gid=dop2 euid=dop2 suid=dop2 fsuid=dop2 egid=dop2 sgid=dop2 fsgid=dop2 tty=pts0 ses=12 comm=ls exe=/usr/lib/cargo/bin/coreutils/ls subj=unconfined key=user-commands
----
type=PROCTITLE msg=audit(07/13/2026 12:16:44.448:1099) : proctitle=sed -e s/\\/\\x5c/g -e s/;/\\x3b/g -e s/[[:cntrl:]]/⍰/g
type=PATH msg=audit(07/13/2026 12:16:44.448:1099) : item=1 name=/lib64/ld-linux-x86-64.so.2 inode=1730435 dev=08:02 mode=file,755 ouid=root ogid=root rdev=00:00 nametype=NORMAL cap_fp=none cap_fi=none cap_fe=0 cap_fver=0 cap_frootid=0
type=PATH msg=audit(07/13/2026 12:16:44.448:1099) : item=0 name=/usr/bin/sed inode=1705250 dev=08:02 mode=file,755 ouid=root ogid=root rdev=00:00 nametype=NORMAL cap_fp=none cap_fi=none cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(07/13/2026 12:16:44.448:1099) : cwd=/home/dop2
type=EXECVE msg=audit(07/13/2026 12:16:44.448:1099) : argc=7 a0=sed a1=-e a2=s/\\/\\x5c/g a3=-e a4=s/;/\\x3b/g a5=-e a6=s/[[:cntrl:]]/⍰/g
type=SYSCALL msg=audit(07/13/2026 12:16:44.448:1099) : arch=x86_64 syscall=execve success=yes exit=0 a0=0x5fa0ff12b440 a1=0x5fa0ff0f1060 a2=0x5fa0ff0e64a0 a3=0x8 items=2 ppid=4989 pid=4991 auid=dop2 uid=dop2 gid=dop2 euid=dop2 suid=dop2 fsuid=dop2 egid=dop2 sgid=dop2 fsgid=dop2 tty=pts0 ses=12 comm=sed exe=/usr/bin/sed subj=unconfined key=user-commands
----
type=PROCTITLE msg=audit(07/13/2026 12:16:49.324:1100) : proctitle=sed -e s/\\/\\x5c/g -e s/;/\\x3b/g -e s/[[:cntrl:]]/⍰/g
type=PATH msg=audit(07/13/2026 12:16:49.324:1100) : item=1 name=/lib64/ld-linux-x86-64.so.2 inode=1730435 dev=08:02 mode=file,755 ouid=root ogid=root rdev=00:00 nametype=NORMAL cap_fp=none cap_fi=none cap_fe=0 cap_fver=0 cap_frootid=0
type=PATH msg=audit(07/13/2026 12:16:49.324:1100) : item=0 name=/usr/bin/sed inode=1705250 dev=08:02 mode=file,755 ouid=root ogid=root rdev=00:00 nametype=NORMAL cap_fp=none cap_fi=none cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(07/13/2026 12:16:49.324:1100) : cwd=/home/dop2
type=EXECVE msg=audit(07/13/2026 12:16:49.324:1100) : argc=7 a0=sed a1=-e a2=s/\\/\\x5c/g a3=-e a4=s/;/\\x3b/g a5=-e a6=s/[[:cntrl:]]/⍰/g
type=SYSCALL msg=audit(07/13/2026 12:16:49.324:1100) : arch=x86_64 syscall=execve success=yes exit=0 a0=0x5fa0ff024930 a1=0x5fa0ff11ecf0 a2=0x5fa0ff0e64a0 a3=0x8 items=2 ppid=4994 pid=4996 auid=dop2 uid=dop2 gid=dop2 euid=dop2 suid=dop2 fsuid=dop2 egid=dop2 sgid=dop2 fsgid=dop2 tty=pts0 ses=12 comm=sed exe=/usr/bin/sed subj=unconfined key=user-commands
----
type=PROCTITLE msg=audit(07/13/2026 12:16:49.325:1101) : proctitle=sudo -l
type=PATH msg=audit(07/13/2026 12:16:49.325:1101) : item=1 name=/lib64/ld-linux-x86-64.so.2 inode=1730435 dev=08:02 mode=file,755 ouid=root ogid=root rdev=00:00 nametype=NORMAL cap_fp=none cap_fi=none cap_fe=0 cap_fver=0 cap_frootid=0
type=PATH msg=audit(07/13/2026 12:16:49.325:1101) : item=0 name=/usr/bin/sudo inode=1707389 dev=08:02 mode=file,suid,755 ouid=root ogid=root rdev=00:00 nametype=NORMAL cap_fp=none cap_fi=none cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(07/13/2026 12:16:49.325:1101) : cwd=/home/dop2
type=EXECVE msg=audit(07/13/2026 12:16:49.325:1101) : argc=2 a0=sudo a1=-l
type=SYSCALL msg=audit(07/13/2026 12:16:49.325:1101) : arch=x86_64 syscall=execve success=yes exit=0 a0=0x5fa0ff128e30 a1=0x5fa0ff129c70 a2=0x5fa0ff0e64a0 a3=0x21 items=2 ppid=4845 pid=4997 auid=dop2 uid=dop2 gid=dop2 euid=root suid=root fsuid=root egid=dop2 sgid=dop2 fsgid=dop2 tty=pts0 ses=12 comm=sudo exe=/usr/lib/cargo/bin/sudo subj=unconfined key=user-commands
----
type=PROCTITLE msg=audit(07/13/2026 12:16:49.330:1103) : proctitle=sed -e s/\\/\\x5c/g -e s/;/\\x3b/g -e s/[[:cntrl:]]/⍰/g
type=PATH msg=audit(07/13/2026 12:16:49.330:1103) : item=1 name=/lib64/ld-linux-x86-64.so.2 inode=1730435 dev=08:02 mode=file,755 ouid=root ogid=root rdev=00:00 nametype=NORMAL cap_fp=none cap_fi=none cap_fe=0 cap_fver=0 cap_frootid=0
type=PATH msg=audit(07/13/2026 12:16:49.330:1103) : item=0 name=/usr/bin/sed inode=1705250 dev=08:02 mode=file,755 ouid=root ogid=root rdev=00:00 nametype=NORMAL cap_fp=none cap_fi=none cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(07/13/2026 12:16:49.330:1103) : cwd=/home/dop2
type=EXECVE msg=audit(07/13/2026 12:16:49.330:1103) : argc=7 a0=sed a1=-e a2=s/\\/\\x5c/g a3=-e a4=s/;/\\x3b/g a5=-e a6=s/[[:cntrl:]]/⍰/g
type=SYSCALL msg=audit(07/13/2026 12:16:49.330:1103) : arch=x86_64 syscall=execve success=yes exit=0 a0=0x5fa0ff12b540 a1=0x5fa0ff0f1060 a2=0x5fa0ff0e64a0 a3=0x8 items=2 ppid=4999 pid=5001 auid=dop2 uid=dop2 gid=dop2 euid=dop2 suid=dop2 fsuid=dop2 egid=dop2 sgid=dop2 fsgid=dop2 tty=pts0 ses=12 comm=sed exe=/usr/bin/sed subj=unconfined key=user-commands
----
type=PROCTITLE msg=audit(07/13/2026 12:16:54.740:1104) : proctitle=sed -e s/\\/\\x5c/g -e s/;/\\x3b/g -e s/[[:cntrl:]]/⍰/g
type=PATH msg=audit(07/13/2026 12:16:54.740:1104) : item=1 name=/lib64/ld-linux-x86-64.so.2 inode=1730435 dev=08:02 mode=file,755 ouid=root ogid=root rdev=00:00 nametype=NORMAL cap_fp=none cap_fi=none cap_fe=0 cap_fver=0 cap_frootid=0
type=PATH msg=audit(07/13/2026 12:16:54.740:1104) : item=0 name=/usr/bin/sed inode=1705250 dev=08:02 mode=file,755 ouid=root ogid=root rdev=00:00 nametype=NORMAL cap_fp=none cap_fi=none cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(07/13/2026 12:16:54.740:1104) : cwd=/home/dop2
type=EXECVE msg=audit(07/13/2026 12:16:54.740:1104) : argc=7 a0=sed a1=-e a2=s/\\/\\x5c/g a3=-e a4=s/;/\\x3b/g a5=-e a6=s/[[:cntrl:]]/⍰/g
type=SYSCALL msg=audit(07/13/2026 12:16:54.740:1104) : arch=x86_64 syscall=execve success=yes exit=0 a0=0x5fa0ff09b070 a1=0x5fa0ff11ecf0 a2=0x5fa0ff0e64a0 a3=0x8 items=2 ppid=5004 pid=5006 auid=dop2 uid=dop2 gid=dop2 euid=dop2 suid=dop2 fsuid=dop2 egid=dop2 sgid=dop2 fsgid=dop2 tty=pts0 ses=12 comm=sed exe=/usr/bin/sed subj=unconfined key=user-commands
----
type=PROCTITLE msg=audit(07/13/2026 12:16:54.742:1105) : proctitle=sudo ausearch -k user-commands -i
type=PATH msg=audit(07/13/2026 12:16:54.742:1105) : item=1 name=/lib64/ld-linux-x86-64.so.2 inode=1730435 dev=08:02 mode=file,755 ouid=root ogid=root rdev=00:00 nametype=NORMAL cap_fp=none cap_fi=none cap_fe=0 cap_fver=0 cap_frootid=0
type=PATH msg=audit(07/13/2026 12:16:54.742:1105) : item=0 name=/usr/bin/sudo inode=1707389 dev=08:02 mode=file,suid,755 ouid=root ogid=root rdev=00:00 nametype=NORMAL cap_fp=none cap_fi=none cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(07/13/2026 12:16:54.742:1105) : cwd=/home/dop2
type=EXECVE msg=audit(07/13/2026 12:16:54.742:1105) : argc=5 a0=sudo a1=ausearch a2=-k a3=user-commands a4=-i
type=SYSCALL msg=audit(07/13/2026 12:16:54.742:1105) : arch=x86_64 syscall=execve success=yes exit=0 a0=0x5fa0ff021810 a1=0x5fa0ff01b2d0 a2=0x5fa0ff0e64a0 a3=0x8 items=2 ppid=4845 pid=5007 auid=dop2 uid=dop2 gid=dop2 euid=root suid=root fsuid=root egid=dop2 sgid=dop2 fsgid=dop2 tty=pts0 ses=12 comm=sudo exe=/usr/lib/cargo/bin/sudo subj=unconfined key=user-commands
----
type=PROCTITLE msg=audit(07/13/2026 12:16:54.742:1106) : proctitle=tail -n 80
type=PATH msg=audit(07/13/2026 12:16:54.742:1106) : item=1 name=/lib64/ld-linux-x86-64.so.2 inode=1730435 dev=08:02 mode=file,755 ouid=root ogid=root rdev=00:00 nametype=NORMAL cap_fp=none cap_fi=none cap_fe=0 cap_fver=0 cap_frootid=0
type=PATH msg=audit(07/13/2026 12:16:54.742:1106) : item=0 name=/usr/bin/tail inode=1704334 dev=08:02 mode=file,755 ouid=root ogid=root rdev=00:00 nametype=NORMAL cap_fp=none cap_fi=none cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(07/13/2026 12:16:54.742:1106) : cwd=/home/dop2
type=EXECVE msg=audit(07/13/2026 12:16:54.742:1106) : argc=3 a0=tail a1=-n a2=80
type=SYSCALL msg=audit(07/13/2026 12:16:54.742:1106) : arch=x86_64 syscall=execve success=yes exit=0 a0=0x5fa0ff021810 a1=0x5fa0ff11d200 a2=0x5fa0ff0e64a0 a3=0x8 items=2 ppid=4845 pid=5008 auid=dop2 uid=dop2 gid=dop2 euid=dop2 suid=dop2 fsuid=dop2 egid=dop2 sgid=dop2 fsgid=dop2 tty=pts0 ses=12 comm=tail exe=/usr/lib/cargo/bin/coreutils/tail subj=unconfined key=user-commands
----
type=PROCTITLE msg=audit(07/13/2026 12:16:54.746:1107) : proctitle=/usr/sbin/unix_chkpwd dop2 chkexpiry
type=PATH msg=audit(07/13/2026 12:16:54.746:1107) : item=1 name=/lib64/ld-linux-x86-64.so.2 inode=1730435 dev=08:02 mode=file,755 ouid=root ogid=root rdev=00:00 nametype=NORMAL cap_fp=none cap_fi=none cap_fe=0 cap_fver=0 cap_frootid=0
type=PATH msg=audit(07/13/2026 12:16:54.746:1107) : item=0 name=/usr/sbin/unix_chkpwd inode=1731314 dev=08:02 mode=file,sgid,755 ouid=root ogid=shadow rdev=00:00 nametype=NORMAL cap_fp=none cap_fi=none cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(07/13/2026 12:16:54.746:1107) : cwd=/home/dop2
type=EXECVE msg=audit(07/13/2026 12:16:54.746:1107) : argc=3 a0=/usr/sbin/unix_chkpwd a1=dop2 a2=chkexpiry
type=SYSCALL msg=audit(07/13/2026 12:16:54.746:1107) : arch=x86_64 syscall=execve success=yes exit=0 a0=0x7063c95f304a a1=0x7ffeea905350 a2=0x7063c95f6028 a3=0x0 items=2 ppid=5007 pid=5009 auid=dop2 uid=root gid=dop2 euid=root suid=root fsuid=root egid=shadow sgid=shadow fsgid=shadow tty=pts0 ses=12 comm=unix_chkpwd exe=/usr/sbin/unix_chkpwd subj=unix-chkpwd key=user-commands
----
type=PROCTITLE msg=audit(07/13/2026 12:16:54.748:1111) : proctitle=ausearch -k user-commands -i
type=PATH msg=audit(07/13/2026 12:16:54.748:1111) : item=1 name=/lib64/ld-linux-x86-64.so.2 inode=1730435 dev=08:02 mode=file,755 ouid=root ogid=root rdev=00:00 nametype=NORMAL cap_fp=none cap_fi=none cap_fe=0 cap_fver=0 cap_frootid=0
type=PATH msg=audit(07/13/2026 12:16:54.748:1111) : item=0 name=/usr/sbin/ausearch inode=1716328 dev=08:02 mode=file,755 ouid=root ogid=root rdev=00:00 nametype=NORMAL cap_fp=none cap_fi=none cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(07/13/2026 12:16:54.748:1111) : cwd=/home/dop2
type=EXECVE msg=audit(07/13/2026 12:16:54.748:1111) : argc=4 a0=ausearch a1=-k a2=user-commands a3=-i
type=SYSCALL msg=audit(07/13/2026 12:16:54.748:1111) : arch=x86_64 syscall=execve success=yes exit=0 a0=0x5f07c52e1a50 a1=0x5f07c52d8090 a2=0x5f07c52d7060 a3=0x8 items=2 ppid=5010 pid=5011 auid=dop2 uid=root gid=root euid=root suid=root fsuid=root egid=root sgid=root fsgid=root tty=pts1 ses=12 comm=ausearch exe=/usr/sbin/ausearch subj=unconfined key=user-commands

#================================== END ========================
```

----
## Короткая шпаргалка

```bash
#Проверить, работает ли auditd.
sudo systemctl status auditd --no-pager

#Статус audit-системы.
sudo auditctl -s

#Показать активные audit-правила.
sudo auditctl -l

#Загрузить правила из `/etc/audit/rules.d/`.
sudo augenrules --load

#Найти события по ключу `user-commands`.
sudo ausearch -k user-commands -i

#Сводный отчёт по запускаемым программам.
sudo aureport -x --summary
```

---
### 14.1 Куда смотреть: auditd запущен

В выводе sudo systemctl status auditd --no-pager это главное место.:
```
Active: active (running)
```
Означает:
> Сервис `auditd` запущен и принимает события от ядра.


Ещё важная строка:
```
Init complete, auditd 4.1.2 listening for events
```
Это значит:
> `auditd` стартовал и слушает audit-события.

Строка:
```
No plugins found, not dispatching events
```

Сейчас данное предупреждение не критично. Оно значит, что auditd не нашёл дополнительные плагины для пересылки событий куда-то ещё. Но локальное логирование работает.

---

### 14.2 Куда смотреть: audit включён и ничего не теряется

Твой вывод:
```bash
enabled 1
failure 1
pid 4148
backlog_limit 8192
lost 0
backlog 0
```

Смотреть особенно сюда:
```bash
enabled 1
lost 0
```

Разбор:
```bash
enabled 1 — audit-система включена
lost 0    — потерянных audit-событий нет
```

`lost 0` — очень хорошая строка. Она значит, что auditd успевает обрабатывать события и пока ничего не потерял. Также:
```bash
backlog_limit 8192
```

Это значит, что наше правило применилось. Мы увеличили буфер audit-событий:
```
-b 8192
```

---
### 14.3 Куда смотреть: правила реально загружены

Вот наш вывод:
```bash
-a always,exit -F arch=b64 -S execve -F auid>=1000 -F auid!=-1 -F key=user-commands
-a always,exit -F arch=b32 -S execve -F auid>=1000 -F auid!=-1 -F key=user-commands
-w /etc/ssh/sshd_config -p wa -k ssh-config
-w /etc/ssh/sshd_config.d -p wa -k ssh-config
-w /etc/sudoers -p wa -k sudoers
-w /etc/sudoers.d -p wa -k sudoers
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/gshadow -p wa -k identity
```

Это прям доказательство, что правила активны. Главное:
```bash
-S execve
-k user-commands
```

Означает:
> Логируем запуск программ пользователями и помечаем эти события ключом `user-commands`.

Ещё:
```bash
-w /etc/ssh/sshd_config -p wa -k ssh-config
```
Означает:
> Следим за изменениями SSH-конфига.


```bash
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
```
Означает:
> Следим за изменениями пользователей и групп.

---
### 14.4 Почему `4294967295` превратилось в `-1`

В файле правил у тебя было:
```bash
-F auid!=4294967295
```

А в активных правилах стало:
```bash
-F auid!=-1
```

Это нормально. `4294967295` — это unsigned-представление значения `-1`. В audit это обычно означает “loginuid не установлен”. Утилита просто показывает это в другом виде. Другими словами:
```bash
auid!=4294967295
#И
auid!=-1
```
в данном контексте означают одно и то же:
> Не логировать события без нормального login UID.

---
### 14.5 Куда смотреть: команды реально логируются

Вот важный кусок:
```bash
type=EXECVE ... argc=3 a0=ls a1=--color=auto a2=/etc/ssh
```

Смотреть сюда:
```bash
type=EXECVE
a0=ls
a2=/etc/ssh
```
Это значит:
> Пользователь запустил команду `ls /etc/ssh`.


Ещё:
```bash
type=PROCTITLE ... proctitle=sudo -l
type=EXECVE ... argc=2 a0=sudo a1=-l
```

Смотреть сюда:
```bash
proctitle=sudo -l
a0=sudo
a1=-l
```

Это значит:
> auditd зафиксировал запуск `sudo -l`.

Ещё важная строка:
```bash
auid=dop2 uid=dop2 euid=root

#Разбор
auid=dop2 # кто изначально вошёл в систему
uid=dop2  # текущий реальный пользователь
euid=root # эффективные права стали root
```
То есть когда ты делаешь `sudo`, auditd всё равно помнит, что изначальный пользователь был `dop2`. Это как раз важно для аудита: нельзя просто сказать “это сделал root”, видно, что root-права получил `dop2`.

---
### 14.6 Почему в логах много `sed`, `tail`, `ausearch`

Это нормально. Ты выполнял команду:
```bash
sudo ausearch -k user-commands -i | tail -n 80
```

И auditd залогировал не только “интересные” команды, но и служебные процессы:
```file
sed
tail
ausearch
unix_chkpwd
```

Почему? Потому что мы сказали auditd:
```txt
логировать execve всех обычных пользователей
```

А `execve` — это запуск любой программы. Команда с pipe:
```bash
sudo ausearch -k user-commands -i | tail -n 80
```

Запускает минимум:
```bash
sudo
ausearch
tail
```
А внутри обработки могут запускаться дополнительные программы. Поэтому лог получается шумным. Это нормально для auditd.

---
### 14.7 Предупреждение `Old style watch rules are slower`

Ты видел:
```file
Old style watch rules are slower
```

Это не ошибка. Это предупреждение, что правила вида считаются “old style watch rules”:
```file
-w /etc/passwd -p wa -k identity
```
Они работают, просто auditd предупреждает, что такой стиль может быть медленнее, чем syscall-based правила. Для учебной практики и jump host это нормально. Главное — `auditctl -l` показывает, что правила активны.

---

### 14.8 Сейчас нужно сделать ещё одну проверку: аудит изменения SSH-конфига

Мы уже доказали `user-commands`. Теперь докажем `ssh-config`. Мы не ломаем файл, просто меняем время изменения. Выполним:
```bash
#Изменить время изменения чтобы зафиксировать в логах:
sudo touch /etc/ssh/sshd_config.d/99-jumphost.conf

#Разбор
sudo  # нужны права администратора
touch # обновить timestamp файла
```


Потом ищем audit-событие:
```bash
sudo ausearch -k ssh-config -i | tail -n 60
```

Если это есть — auditd отслеживает изменения SSH-конфигурации. Куда смотреть:
```bash
key="ssh-config"
name="/etc/ssh/sshd_config.d/99-jumphost.conf"
```

---
### 14.9 Проверка пользователей и групп

Теперь проверим `identity`. Безопасно сделаем `touch` файла `/etc/group` не надо — это системный файл, лучше протестировать реальным действием через группу. Например, можно создать временную группу:

```bash
sudo groupadd audit-test-group
sudo groupdel audit-test-group
```

Потом:
```bash
sudo ausearch -k identity -i | tail -n 80

#Вывод:
dop2@dop2:~$ sudo ausearch -k identity -i | tail -n 80
type=SOCKADDR msg=audit(07/13/2026 12:14:56.513:1078) : saddr={ saddr_fam=netlink nlnk-fam=16 nlnk-pid=0 }
type=SYSCALL msg=audit(07/13/2026 12:14:56.513:1078) : arch=x86_64 syscall=sendto success=yes exit=1076 a0=0x3 a1=0x7fff446a7bb0 a2=0x434 a3=0x0 items=1 ppid=4930 pid=4946 auid=dop2 uid=root gid=root euid=root suid=root fsuid=root egid=root sgid=root fsgid=root tty=pts1 ses=12 comm=auditctl exe=/usr/sbin/auditctl subj=unconfined key=(null)
type=CONFIG_CHANGE msg=audit(07/13/2026 12:14:56.513:1078) : auid=dop2 ses=12 subj=unconfined op=add_rule key=identity list=exit res=yes
----
type=PROCTITLE msg=audit(07/13/2026 12:14:56.513:1079) : proctitle=/sbin/auditctl -R /etc/audit/audit.rules
type=PATH msg=audit(07/13/2026 12:14:56.513:1079) : item=0 name=/etc/ inode=786433 dev=08:02 mode=dir,755 ouid=root ogid=root rdev=00:00 nametype=PARENT cap_fp=none cap_fi=none cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(07/13/2026 12:14:56.513:1079) : cwd=/home/dop2
type=SOCKADDR msg=audit(07/13/2026 12:14:56.513:1079) : saddr={ saddr_fam=netlink nlnk-fam=16 nlnk-pid=0 }
type=SYSCALL msg=audit(07/13/2026 12:14:56.513:1079) : arch=x86_64 syscall=sendto success=yes exit=1076 a0=0x3 a1=0x7fff446a7bb0 a2=0x434 a3=0x0 items=1 ppid=4930 pid=4946 auid=dop2 uid=root gid=root euid=root suid=root fsuid=root egid=root sgid=root fsgid=root tty=pts1 ses=12 comm=auditctl exe=/usr/sbin/auditctl subj=unconfined key=(null)
type=CONFIG_CHANGE msg=audit(07/13/2026 12:14:56.513:1079) : auid=dop2 ses=12 subj=unconfined op=add_rule key=identity list=exit res=yes
----
type=PROCTITLE msg=audit(07/13/2026 12:14:56.513:1080) : proctitle=/sbin/auditctl -R /etc/audit/audit.rules
type=PATH msg=audit(07/13/2026 12:14:56.513:1080) : item=0 name=/etc/ inode=786433 dev=08:02 mode=dir,755 ouid=root ogid=root rdev=00:00 nametype=PARENT cap_fp=none cap_fi=none cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(07/13/2026 12:14:56.513:1080) : cwd=/home/dop2
type=SOCKADDR msg=audit(07/13/2026 12:14:56.513:1080) : saddr={ saddr_fam=netlink nlnk-fam=16 nlnk-pid=0 }
type=SYSCALL msg=audit(07/13/2026 12:14:56.513:1080) : arch=x86_64 syscall=sendto success=yes exit=1076 a0=0x3 a1=0x7fff446a7bb0 a2=0x434 a3=0x0 items=1 ppid=4930 pid=4946 auid=dop2 uid=root gid=root euid=root suid=root fsuid=root egid=root sgid=root fsgid=root tty=pts1 ses=12 comm=auditctl exe=/usr/sbin/auditctl subj=unconfined key=(null)
type=CONFIG_CHANGE msg=audit(07/13/2026 12:14:56.513:1080) : auid=dop2 ses=12 subj=unconfined op=add_rule key=identity list=exit res=yes
----
type=PROCTITLE msg=audit(07/13/2026 12:14:56.513:1081) : proctitle=/sbin/auditctl -R /etc/audit/audit.rules
type=PATH msg=audit(07/13/2026 12:14:56.513:1081) : item=0 name=/etc/ inode=786433 dev=08:02 mode=dir,755 ouid=root ogid=root rdev=00:00 nametype=PARENT cap_fp=none cap_fi=none cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(07/13/2026 12:14:56.513:1081) : cwd=/home/dop2
type=SOCKADDR msg=audit(07/13/2026 12:14:56.513:1081) : saddr={ saddr_fam=netlink nlnk-fam=16 nlnk-pid=0 }
type=SYSCALL msg=audit(07/13/2026 12:14:56.513:1081) : arch=x86_64 syscall=sendto success=yes exit=1076 a0=0x3 a1=0x7fff446a7bb0 a2=0x434 a3=0x0 items=1 ppid=4930 pid=4946 auid=dop2 uid=root gid=root euid=root suid=root fsuid=root egid=root sgid=root fsgid=root tty=pts1 ses=12 comm=auditctl exe=/usr/sbin/auditctl subj=unconfined key=(null)
type=CONFIG_CHANGE msg=audit(07/13/2026 12:14:56.513:1081) : auid=dop2 ses=12 subj=unconfined op=add_rule key=identity list=exit res=yes
----
type=PROCTITLE msg=audit(07/13/2026 12:45:58.365:1158) : proctitle=groupadd audit-test-group
type=PATH msg=audit(07/13/2026 12:45:58.365:1158) : item=0 name=/etc/group inode=788765 dev=08:02 mode=file,644 ouid=root ogid=root rdev=00:00 nametype=NORMAL cap_fp=none cap_fi=none cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(07/13/2026 12:45:58.365:1158) : cwd=/home/dop2
type=SYSCALL msg=audit(07/13/2026 12:45:58.365:1158) : arch=x86_64 syscall=openat success=yes exit=5 a0=AT_FDCWD a1=0x558d8b898ac0 a2=O_RDWR|O_NOCTTY|O_NONBLOCK|O_NOFOLLOW|O_CLOEXEC a3=0x0 items=1 ppid=5117 pid=5118 auid=dop2 uid=root gid=root euid=root suid=root fsuid=root egid=root sgid=root fsgid=root tty=pts1 ses=12 comm=groupadd exe=/usr/sbin/groupadd subj=unconfined key=identity
----
type=PROCTITLE msg=audit(07/13/2026 12:45:58.365:1159) : proctitle=groupadd audit-test-group
type=PATH msg=audit(07/13/2026 12:45:58.365:1159) : item=0 name=/etc/gshadow inode=788761 dev=08:02 mode=file,640 ouid=root ogid=shadow rdev=00:00 nametype=NORMAL cap_fp=none cap_fi=none cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(07/13/2026 12:45:58.365:1159) : cwd=/home/dop2
type=SYSCALL msg=audit(07/13/2026 12:45:58.365:1159) : arch=x86_64 syscall=openat success=yes exit=6 a0=AT_FDCWD a1=0x558d8b898f20 a2=O_RDWR|O_NOCTTY|O_NONBLOCK|O_NOFOLLOW|O_CLOEXEC a3=0x0 items=1 ppid=5117 pid=5118 auid=dop2 uid=root gid=root euid=root suid=root fsuid=root egid=root sgid=root fsgid=root tty=pts1 ses=12 comm=groupadd exe=/usr/sbin/groupadd subj=unconfined key=identity
----
type=PROCTITLE msg=audit(07/13/2026 12:45:58.377:1160) : proctitle=groupadd audit-test-group
type=PATH msg=audit(07/13/2026 12:45:58.377:1160) : item=4 name=/etc/group inode=788764 dev=08:02 mode=file,644 ouid=root ogid=root rdev=00:00 nametype=CREATE cap_fp=none cap_fi=none cap_fe=0 cap_fver=0 cap_frootid=0
type=PATH msg=audit(07/13/2026 12:45:58.377:1160) : item=3 name=/etc/group inode=788765 dev=08:02 mode=file,644 ouid=root ogid=root rdev=00:00 nametype=DELETE cap_fp=none cap_fi=none cap_fe=0 cap_fver=0 cap_frootid=0
type=PATH msg=audit(07/13/2026 12:45:58.377:1160) : item=2 name=/etc/group+ inode=788764 dev=08:02 mode=file,644 ouid=root ogid=root rdev=00:00 nametype=DELETE cap_fp=none cap_fi=none cap_fe=0 cap_fver=0 cap_frootid=0
type=PATH msg=audit(07/13/2026 12:45:58.377:1160) : item=1 name=/etc/ inode=786433 dev=08:02 mode=dir,755 ouid=root ogid=root rdev=00:00 nametype=PARENT cap_fp=none cap_fi=none cap_fe=0 cap_fver=0 cap_frootid=0
type=PATH msg=audit(07/13/2026 12:45:58.377:1160) : item=0 name=/etc/ inode=786433 dev=08:02 mode=dir,755 ouid=root ogid=root rdev=00:00 nametype=PARENT cap_fp=none cap_fi=none cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(07/13/2026 12:45:58.377:1160) : cwd=/home/dop2
type=SYSCALL msg=audit(07/13/2026 12:45:58.377:1160) : arch=x86_64 syscall=rename success=yes exit=0 a0=0x7ffc82f2e9a0 a1=0x558d8b898ac0 a2=0x7ffc82f2e910 a3=0x100 items=5 ppid=5117 pid=5118 auid=dop2 uid=root gid=root euid=root suid=root fsuid=root egid=root sgid=root fsgid=root tty=pts1 ses=12 comm=groupadd exe=/usr/sbin/groupadd subj=unconfined key=identity
----
type=PROCTITLE msg=audit(07/13/2026 12:45:58.381:1162) : proctitle=groupadd audit-test-group
type=PATH msg=audit(07/13/2026 12:45:58.381:1162) : item=4 name=/etc/gshadow inode=788762 dev=08:02 mode=file,640 ouid=root ogid=shadow rdev=00:00 nametype=CREATE cap_fp=none cap_fi=none cap_fe=0 cap_fver=0 cap_frootid=0
type=PATH msg=audit(07/13/2026 12:45:58.381:1162) : item=3 name=/etc/gshadow inode=788761 dev=08:02 mode=file,640 ouid=root ogid=shadow rdev=00:00 nametype=DELETE cap_fp=none cap_fi=none cap_fe=0 cap_fver=0 cap_frootid=0
type=PATH msg=audit(07/13/2026 12:45:58.381:1162) : item=2 name=/etc/gshadow+ inode=788762 dev=08:02 mode=file,640 ouid=root ogid=shadow rdev=00:00 nametype=DELETE cap_fp=none cap_fi=none cap_fe=0 cap_fver=0 cap_frootid=0
type=PATH msg=audit(07/13/2026 12:45:58.381:1162) : item=1 name=/etc/ inode=786433 dev=08:02 mode=dir,755 ouid=root ogid=root rdev=00:00 nametype=PARENT cap_fp=none cap_fi=none cap_fe=0 cap_fver=0 cap_frootid=0
type=PATH msg=audit(07/13/2026 12:45:58.381:1162) : item=0 name=/etc/ inode=786433 dev=08:02 mode=dir,755 ouid=root ogid=root rdev=00:00 nametype=PARENT cap_fp=none cap_fi=none cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(07/13/2026 12:45:58.381:1162) : cwd=/home/dop2
type=SYSCALL msg=audit(07/13/2026 12:45:58.381:1162) : arch=x86_64 syscall=rename success=yes exit=0 a0=0x7ffc82f2e9a0 a1=0x558d8b898f20 a2=0x7ffc82f2e910 a3=0x100 items=5 ppid=5117 pid=5118 auid=dop2 uid=root gid=root euid=root suid=root fsuid=root egid=root sgid=root fsgid=root tty=pts1 ses=12 comm=groupadd exe=/usr/sbin/groupadd subj=unconfined key=identity
----
type=PROCTITLE msg=audit(07/13/2026 12:46:07.164:1176) : proctitle=groupdel audit-test-group
type=PATH msg=audit(07/13/2026 12:46:07.164:1176) : item=0 name=/etc/group inode=788764 dev=08:02 mode=file,644 ouid=root ogid=root rdev=00:00 nametype=NORMAL cap_fp=none cap_fi=none cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(07/13/2026 12:46:07.164:1176) : cwd=/home/dop2
type=SYSCALL msg=audit(07/13/2026 12:46:07.164:1176) : arch=x86_64 syscall=openat success=yes exit=5 a0=AT_FDCWD a1=0x63026a2659e0 a2=O_RDWR|O_NOCTTY|O_NONBLOCK|O_NOFOLLOW|O_CLOEXEC a3=0x0 items=1 ppid=5133 pid=5134 auid=dop2 uid=root gid=root euid=root suid=root fsuid=root egid=root sgid=root fsgid=root tty=pts1 ses=12 comm=groupdel exe=/usr/sbin/groupdel subj=unconfined key=identity
----
type=PROCTITLE msg=audit(07/13/2026 12:46:07.164:1177) : proctitle=groupdel audit-test-group
type=PATH msg=audit(07/13/2026 12:46:07.164:1177) : item=0 name=/etc/gshadow inode=788762 dev=08:02 mode=file,640 ouid=root ogid=shadow rdev=00:00 nametype=NORMAL cap_fp=none cap_fi=none cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(07/13/2026 12:46:07.164:1177) : cwd=/home/dop2
type=SYSCALL msg=audit(07/13/2026 12:46:07.164:1177) : arch=x86_64 syscall=openat success=yes exit=6 a0=AT_FDCWD a1=0x63026a265e40 a2=O_RDWR|O_NOCTTY|O_NONBLOCK|O_NOFOLLOW|O_CLOEXEC a3=0x0 items=1 ppid=5133 pid=5134 auid=dop2 uid=root gid=root euid=root suid=root fsuid=root egid=root sgid=root fsgid=root tty=pts1 ses=12 comm=groupdel exe=/usr/sbin/groupdel subj=unconfined key=identity
----
type=PROCTITLE msg=audit(07/13/2026 12:46:07.167:1178) : proctitle=groupdel audit-test-group
type=PATH msg=audit(07/13/2026 12:46:07.167:1178) : item=4 name=/etc/group inode=788765 dev=08:02 mode=file,644 ouid=root ogid=root rdev=00:00 nametype=CREATE cap_fp=none cap_fi=none cap_fe=0 cap_fver=0 cap_frootid=0
type=PATH msg=audit(07/13/2026 12:46:07.167:1178) : item=3 name=/etc/group inode=788764 dev=08:02 mode=file,644 ouid=root ogid=root rdev=00:00 nametype=DELETE cap_fp=none cap_fi=none cap_fe=0 cap_fver=0 cap_frootid=0
type=PATH msg=audit(07/13/2026 12:46:07.167:1178) : item=2 name=/etc/group+ inode=788765 dev=08:02 mode=file,644 ouid=root ogid=root rdev=00:00 nametype=DELETE cap_fp=none cap_fi=none cap_fe=0 cap_fver=0 cap_frootid=0
type=PATH msg=audit(07/13/2026 12:46:07.167:1178) : item=1 name=/etc/ inode=786433 dev=08:02 mode=dir,755 ouid=root ogid=root rdev=00:00 nametype=PARENT cap_fp=none cap_fi=none cap_fe=0 cap_fver=0 cap_frootid=0
type=PATH msg=audit(07/13/2026 12:46:07.167:1178) : item=0 name=/etc/ inode=786433 dev=08:02 mode=dir,755 ouid=root ogid=root rdev=00:00 nametype=PARENT cap_fp=none cap_fi=none cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(07/13/2026 12:46:07.167:1178) : cwd=/home/dop2
type=SYSCALL msg=audit(07/13/2026 12:46:07.167:1178) : arch=x86_64 syscall=rename success=yes exit=0 a0=0x7ffc715a0ab0 a1=0x63026a2659e0 a2=0x7ffc715a0a20 a3=0x100 items=5 ppid=5133 pid=5134 auid=dop2 uid=root gid=root euid=root suid=root fsuid=root egid=root sgid=root fsgid=root tty=pts1 ses=12 comm=groupdel exe=/usr/sbin/groupdel subj=unconfined key=identity
----
type=PROCTITLE msg=audit(07/13/2026 12:46:07.170:1180) : proctitle=groupdel audit-test-group
type=PATH msg=audit(07/13/2026 12:46:07.170:1180) : item=4 name=/etc/gshadow inode=788761 dev=08:02 mode=file,640 ouid=root ogid=shadow rdev=00:00 nametype=CREATE cap_fp=none cap_fi=none cap_fe=0 cap_fver=0 cap_frootid=0
type=PATH msg=audit(07/13/2026 12:46:07.170:1180) : item=3 name=/etc/gshadow inode=788762 dev=08:02 mode=file,640 ouid=root ogid=shadow rdev=00:00 nametype=DELETE cap_fp=none cap_fi=none cap_fe=0 cap_fver=0 cap_frootid=0
type=PATH msg=audit(07/13/2026 12:46:07.170:1180) : item=2 name=/etc/gshadow+ inode=788761 dev=08:02 mode=file,640 ouid=root ogid=shadow rdev=00:00 nametype=DELETE cap_fp=none cap_fi=none cap_fe=0 cap_fver=0 cap_frootid=0
type=PATH msg=audit(07/13/2026 12:46:07.170:1180) : item=1 name=/etc/ inode=786433 dev=08:02 mode=dir,755 ouid=root ogid=root rdev=00:00 nametype=PARENT cap_fp=none cap_fi=none cap_fe=0 cap_fver=0 cap_frootid=0
type=PATH msg=audit(07/13/2026 12:46:07.170:1180) : item=0 name=/etc/ inode=786433 dev=08:02 mode=dir,755 ouid=root ogid=root rdev=00:00 nametype=PARENT cap_fp=none cap_fi=none cap_fe=0 cap_fver=0 cap_frootid=0
type=CWD msg=audit(07/13/2026 12:46:07.170:1180) : cwd=/home/dop2
type=SYSCALL msg=audit(07/13/2026 12:46:07.170:1180) : arch=x86_64 syscall=rename success=yes exit=0 a0=0x7ffc715a0ab0 a1=0x63026a265e40 a2=0x7ffc715a0a20 a3=0x100 items=5 ppid=5133 pid=5134 auid=dop2 uid=root gid=root euid=root suid=root fsuid=root egid=root sgid=root fsgid=root tty=pts1 ses=12 comm=groupdel exe=/usr/sbin/groupdel subj=unconfined key=identity
```

Это докажет, что auditd видит изменения пользователей/групп. Куда смотреть:
```bash
/etc/group
/etc/gshadow
groupadd
groupdel
key="identity"
```

---

---
## 15. Делаем SSH login alert script

Создадим скрипт:
```bash
#Создаем скрипт для наших алертов 
sudo nano /usr/local/bin/ssh-login-alert.sh

#Вставляем код
#!/usr/bin/env bash

LOG_FILE="/var/log/ssh-login-alerts.log"

{
  echo "========================================"
  echo "SSH LOGIN ALERT"
  echo "Time: $(date --iso-8601=seconds)"
  echo "User: ${PAM_USER:-unknown}"
  echo "Remote host: ${PAM_RHOST:-unknown}"
  echo "Service: ${PAM_SERVICE:-unknown}"
  echo "TTY: ${PAM_TTY:-unknown}"
  echo "Server: $(hostname -f 2>/dev/null || hostname)"
  echo "========================================"
  echo
} >> "$LOG_FILE"

exit 0
```

**Разбор скрипта:**

Это shebang. Он говорит системе:
> Запускай этот файл через Bash.
```conf
#!/usr/bin/env bash
```

Файл, куда будем писать алерты.
```conf
LOG_FILE="/var/log/ssh-login-alerts.log"
```

Пользователь, который вошёл.
```conf
PAM_USER
```

Удалённый IP или hostname, откуда пришло подключение.
```conf
PAM_RHOST
```

Сервис PAM. Для SSH обычно будет `sshd`.
```conf
PAM_SERVICE
```

Терминал/сессия, если есть.
```conf
PAM_TTY
```

Добавляет запись в конец файла, не перезаписывая старые алерты.
```conf
>> "$LOG_FILE"
```

Очень важно. Скрипт должен завершиться успешно, чтобы не сломать логин.
```conf
exit 0
```

---
## 16. Делаем скрипт исполняемым

```bash
#Делаем наш скрипт запускаемым
sudo chmod 755 /usr/local/bin/ssh-login-alert.sh

#Проверяем скрипт, на то что у него появились нужные права -rwxr-xr-x
ls -l /usr/local/bin/ssh-login-alert.sh

#Вывод:
dop2@dop2:~$ ls -l /usr/local/bin/ssh-login-alert.sh
-rwxr-xr-x 1 root root 476 Jul 13 13:53 /usr/local/bin/ssh-login-alert.sh
```

---
## 17. Создаём файл лога для ssh и права

```bash
#Создание файла для алертов ssh
sudo touch /var/log/ssh-login-alerts.log

#Выдача прав на файл для записи
sudo chmod 640 /var/log/ssh-login-alerts.log

#Меняем владельца и группу скрипта

sudo chown root:adm /var/log/ssh-login-alerts.log

#Разбор:
touch # создать файл, если его нет
chmod 640 # root может читать/писать, группа adm читать, остальные ничего
chown root:adm # владелец root, группа adm
```

---
### 18. Подключаем скрипт к PAM SSH

Открой:
```bash
sudo nano /etc/pam.d/sshd
```

Надо добавить эту строку в конец:
```conf
session optional pam_exec.so seteuid /usr/local/bin/ssh-login-alert.sh
```

**Разбор PAM-строки:**

Это PAM-этап сессии. Он выполняется при открытии/закрытии пользовательской сессии.
```
session
```

Если скрипт вдруг завершится ошибкой, логин не должен сломаться.
```
optional
```

PAM-модуль, который запускает внешнюю команду.
```
pam_exec.so
```

Запускать с эффективным UID. Для нашего случая нормально.
```
seteuid
```

Наш скрипт.
```
/usr/local/bin/ssh-login-alert.sh
```

---
## 19. Проверяем PAM-конфиг осторожно

PAM очень чувствительный. Поэтому, yе закрываtv текущую SSH-сессию. Открываем новое окно и подключаемся: (Если вошёл — хорошо.)

```bash
ssh -p 2222 dop2@192.168.31.179
```

Теперь на сервере проверяем лог:
```bash
#ПРоверяем последние 30 строк в логе
sudo tail -n 30 /var/log/ssh-login-alerts.log

#Вывод
dop2@dop2:~$ sudo tail -n 30 /var/log/ssh-login-alerts.log
========================================
SSH LOGIN ALERT
Time: 2026-07-13T14:08:45+00:00
User: dop2
Remote host: 192.168.31.150
Service: sshd
TTY: ssh
Server: dop2
========================================
```

Если видим строки ниже, это значит, что PAM передал скрипту данные о SSH-входе. Куда смотреть:
```bash
User: dop2
Remote host:
Service: sshd
```

---
## 20. Также проверим через journal

Можно посмотреть SSH-логи через journalctl:
```bash
#Эта команда запрашивает логи конкретного системного юнита напрямую из базы данных systemd-journald
sudo journalctl -u ssh --since "10 minutes ago" --no-pager

#Эта команда запрашивает вообще все системные логи за 10 минут, а затем фильтрует их по ключевому слову.
sudo journalctl --since "10 minutes ago" | grep -i sshd

#Разбор команд:
1. sudo journalctl -u ssh --since "10 minutes ago" --no-pager

sudo # запускает команду с правами администратора. Без этого у вас не будет доступа к большинству системных логов.
journalctl # утилита для фильтрации и просмотра логов, управляемых системой systemd.
-u ssh # флаг --unit. Он приказывает показать логи только для конкретной службы — в данном случае ssh (в некоторых дистрибутивах, например Red Hat/CentOS, она называется sshd).
--since "10 minutes ago" #временной фильтр. Ограничивает вывод событиями, которые произошли ровно за последние 10 минут.
--no-pager # отменяет автоматический вывод через утилиту less или more. Весь текст лога выведется в терминал сразу, без необходимости листать его кнопками. Это удобно для копирования или автоматизации в скриптах.

==================================================================
2. sudo journalctl --since "10 minutes ago" | grep -i sshd

sudo journalctl --since "10 minutes ago" #выгружает абсолютно все системные сообщения (от ядра, сети, графической оболочки, всех сервисов), которые произошли за последние 10 минут.
| (pipe / конвейер) # перенаправляет огромный текстовый поток из первой команды на вход второй команде.
grep #утилита для поиска строк по шаблону.
-i # флаг ignore-case. Делает поиск нечувствительным к регистру (найдет и sshd, и SSHD, и Sshd).
sshd # поисковый запрос. Ищет сообщения, где упоминается имя демона SSH (sshd).
```


## ИТОГОВАЯ ПРОВЕРКА ЛОГИРОВАНИЯ:

```bash
#Провенряем системный журнал и запрашиваем данные конкретного пользователя
dop2@dop2:~$ sudo journalctl -u ssh --since "10 minutes ago" --no-pager
Jul 13 14:08:35 dop2 sshd-session[5567]: Accepted password for dop2 from 192.168.31.150 port 62723 ssh2
Jul 13 14:08:35 dop2 sshd-session[5567]: pam_unix(sshd:session): session opened for user dop2(uid=1000) by dop2(uid=0)

#Проверяем весь системный журнал и фильтруем по нужному сервису 
dop2@dop2:~$ sudo journalctl --since "10 minutes ago" | grep -i sshd
Jul 13 14:07:07 dop2 sudo[5557]: dop2 : TTY=/dev/pts/0 ; PWD=/home/dop2 ; USER=root ; COMMAND=/usr/bin/nano /etc/pam.d/sshd
Jul 13 14:08:35 dop2 sshd-session[5567]: Accepted password for dop2 from 192.168.31.150 port 62723 ssh2
Jul 13 14:08:35 dop2 sshd-session[5567]: pam_unix(sshd:session): session opened for user dop2(uid=1000) by dop2(uid=0)

#Смотрим нужный лог и его аллерты
dop2@dop2:~$ sudo tail -n 30 /var/log/ssh-login-alerts.log
========================================
SSH LOGIN ALERT
Time: 2026-07-13T14:08:45+00:00
User: dop2
Remote host: 192.168.31.150
Service: sshd
TTY: ssh
Server: dop2
========================================

========================================
SSH LOGIN ALERT
Time: 2026-07-13T14:23:22+00:00
User: dop2
Remote host: 192.168.31.150
Service: sshd
TTY: ssh
Server: dop2
========================================

========================================
SSH LOGIN ALERT
Time: 2026-07-13T14:23:35+00:00
User: dop2
Remote host: 192.168.31.150
Service: sshd
TTY: ssh
Server: dop2
========================================

dop2@dop2:~$
```


## Дополнительная работа по ротации логов. ВАЖНО

Один production-штрих: logrotate для нашего alert-файла

Сейчас наш лог будет расти бесконечно. В production так нельзя. Нужно добавить ротацию логов.:
```
/var/log/ssh-login-alerts.log
```

Необходимо создать файл:
```bash
#Файл для настройки ротации логов
sudo nano /etc/logrotate.d/ssh-login-alerts

#Что должно быть внутри файла для ротации
/var/log/ssh-login-alerts.log {
    weekly
    rotate 12
    compress
    missingok
    notifempty
    create 0640 root adm
}

#Разбор строк файла
weekly # ротировать раз в неделю
rotate 12 # хранить 12 старых архивов
compress # сжимать старые логи
missingok # не ругаться, если файла нет
notifempty # не ротировать пустой файл
create 0640 root adm # новый файл создать с правами 0640, владелец root, группа adm
```

Проверить без реальной ротации:
```bash
#Проверка без реальной ротации
sudo logrotate -d /etc/logrotate.d/ssh-login-alerts


#Разбор:
#Ключ означает debug mode: показать, что logrotate сделал бы, но ничего не менять.:
-d
```

---

**Мини-проверка перед закрытием блока**

Выполните. Если ошибок нет — блок **“Логирование и аудит”** можно закрывать.:
```bash
sudo tail -n 5 /var/log/ssh-login-alerts.log
sudo logrotate -d /etc/logrotate.d/ssh-login-alerts
```

---
# 4.🔥 Сетевые правила (iptables)

## Цель блока

Мы хотим получить такую логику:
```bash
INPUT:
  разрешить уже установленные соединения
  разрешить localhost
  разрешить SSH 2222 только с твоего IP
  ограничить новые SSH-подключения: 3 в минуту
  всё остальное запретить

OUTPUT:
  разрешить уже установленные соединения
  разрешить localhost
  разрешить DNS
  разрешить нужные сервисы, например apt через HTTP/HTTPS
  разрешить SSH-туннели только к приватной сети
  остальной исходящий интернет запретить

FORWARD:
  по умолчанию запретить
```

---
## 0. Важная теория: INPUT, OUTPUT, FORWARD

В iptables есть цепочки. Для нас главные:
```bash
INPUT   — входящий трафик к самому jump host
OUTPUT  — исходящий трафик, который создаёт сам jump host
FORWARD — трафик, который проходит через сервер как через роутер
```

Например:
```bash
ssh -p 2222 dop2@192.168.31.179
```

Это входящее подключение к jump host, значит цепочка:
```
INPUT
```

А когда jump host сам идёт в DNS или apt-репозиторий, это:
```
OUTPUT
```

Если сервер маршрутизирует чужие пакеты между интерфейсами, это:
```
FORWARD
```

Твои SSH-туннели `-L` чаще всего проходят через процесс `sshd` на jump host и создают исходящее соединение от самого jump host к целевому адресу. Поэтому для ограничения туннелей нам важна цепочка **OUTPUT**, а не только FORWARD.

В iptables правила находятся в таблицах и цепочках; по умолчанию при обычном `iptables -L` используется таблица `filter`, а правила проверяются по цепочке сверху вниз.

----
## 1. Сначала фиксируем наши реальные IP

Из прошлых выводов у нас было:

```
jump host: 192.168.31.179
клиент Windows: 192.168.31.150
вторая сеть jump host: 192.168.56.101
```

Для нашей лабораторной схемы возьмём:
```
ALLOWED_SSH_IP=192.168.31.150
SSH_PORT=2222
PRIVATE_NET=192.168.56.0/24
```

Смысл:

```
192.168.31.150 — только с этого IP разрешаем SSH
2222 — наш SSH-порт
192.168.56.0/24 — приватная сеть за jump host
```

---
## 2. Проверяем текущие правила

На jump host выполни:
```bash
sudo iptables -S
sudo iptables -L -n -v
sudo iptables -t nat -S
```

Куда смотреть. Это политики по умолчанию:
```bash
-P INPUT
-P FORWARD
-P OUTPUT
```

Если там, значит входящий трафик по умолчанию разрешён:
```bash
-P INPUT ACCEPT
```

Если там, то значит входящий трафик по умолчанию запрещён:
```bash
-P INPUT DROP
```

## 3. Делаем backup текущих правил

Обязательно, делаем бэкап наших конфигов перед изменением:
```bash
#Создаем папку с нашими бэкапами
sudo mkdir -p ~/jumphost-backups/iptables

#Сохранения до 
sudo iptables-save | sudo tee ~/jumphost-backups/iptables/iptables-before-$(date +%F-%H%M%S).rules >/dev/null

#Сохранения после
sudo iptables-save | sudo tee ~/jumphost-backups/iptables/iptables-last-good.rules >/dev/null

#Разбор:
iptables-save — вывести все текущие правила
tee файл       — записать вывод в файл
>/dev/null     — не печатать весь ruleset в терминал
```

Файл iptables-last-good.rules будет нашей точкой отката:
```
/root/jumphost-backups/iptables/iptables-last-good.rules
```

Сохранение и восстановление правил можно делать через `iptables-save` и `iptables-restore`; такой подход также описан в учебном материале.

---
## 4. Делаем аварийный авто-откат

Это страховка. Если мы случайно заблокируем SSH, через 3 минуты правила сами откатятся. Создай rollback-скрипт:
```bash
#Создания скрипта для отката
sudo nano ~/jumphost-backups/iptables/rollback-iptables.sh


#Вставь:

#!/usr/bin/env bash
iptables-restore < ~/jumphost-backups/iptables/iptables-last-good.rules
```

Теперь делаем наш скрипт исполняемым:
```bash
sudo chmod 700 ~/jumphost-backups/iptables/rollback-iptables.sh
```

Теперь запускаем отложенный rollback через systemd:
```bash
sudo systemd-run --unit=iptables-rollback --on-active=3m ~/jumphost-backups/iptables/rollback-iptables.sh
```

Куда смотреть:
```bash
Running timer as unit: iptables-rollback.timer
```

Проверить таймер:
```bash
#Просмотра лист запусков по времени с поиском кокретной службы
systemctl list-timers | grep iptables-rollback

#ывод команды:
dop2@dop2:~$ systemctl list-timers | grep iptables-rollback
Mon 2026-07-13 15:42:47 UTC 2min 50s -                                      - iptables-rollback.timer        iptables-rollback.service

dop2@dop2:~$ systemctl list-timers | grep iptables-rollback
Mon 2026-07-13 15:42:47 UTC 2min 46s -                                      - iptables-rollback.timer        iptables-rollback.service

dop2@dop2:~$ systemctl list-timers | grep iptables-rollback
Mon 2026-07-13 15:42:47 UTC 2min 45s -                                      - iptables-rollback.timer        iptables-rollback.service
```

!!! Важно: если всё проверим и SSH не отвалится, мы отменим откат.

----
## 5. Создаём скрипт с правилами

Так безопаснее и чище, чем вводить 30 команд руками. Необходимо открыть в редакторе файл и вставить код для исполняемого скрипта:
```bash
#Команда для создания файла скрипта
sudo nano /root/jumphost-backups/iptables/apply-jumphost-iptables.sh

================================================

#Необходимо вставить
#!/usr/bin/env bash
set -euo pipefail

SSH_PORT="2222"
ALLOWED_SSH_IP="192.168.31.150"
PRIVATE_NET="192.168.56.0/24"

# Очистить старые правила filter-таблицы
iptables -F
iptables -X

# Базовые политики
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# 1. Разрешить loopback
iptables -A INPUT  -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# 2. Разрешить уже установленные соединения
iptables -A INPUT  -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# 3. Отбрасывать битые пакеты
iptables -A INPUT  -m conntrack --ctstate INVALID -j DROP
iptables -A OUTPUT -m conntrack --ctstate INVALID -j DROP

# 4. SSH rate limiting: максимум 3 новых SSH-подключения в минуту с разрешённого IP
iptables -A INPUT -p tcp -s "$ALLOWED_SSH_IP" --dport "$SSH_PORT" \
  -m conntrack --ctstate NEW \
  -m limit --limit 3/min --limit-burst 3 \
  -j ACCEPT

# 5. Всё лишнее на SSH логируем и дропаем
iptables -A INPUT -p tcp --dport "$SSH_PORT" \
  -m limit --limit 5/min \
  -j LOG --log-prefix "IPTABLES SSH DROP: " --log-level 4

iptables -A INPUT -p tcp --dport "$SSH_PORT" -j DROP

# 6. Разрешить DNS-запросы с jump host
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

# 7. Разрешить нужные сервисы для обновлений пакетов
iptables -A OUTPUT -p tcp --dport 80 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 443 -j ACCEPT

# 8. Разрешить SSH-туннелям ходить только в приватную сеть
iptables -A OUTPUT -p tcp -d "$PRIVATE_NET" -j ACCEPT

# 9. Разрешить учебный локальный tunnel-test на самом jump host
iptables -A OUTPUT -p tcp -d 127.0.0.1 --dport 9000 -j ACCEPT

# 10. Логировать заблокированный исходящий трафик, но с лимитом, чтобы не заспамить логи
iptables -A OUTPUT \
  -m limit --limit 5/min \
  -j LOG --log-prefix "IPTABLES OUTPUT DROP: " --log-level 4

# Всё остальное упадёт в policy DROP
```

Сделаем исполняемым:
```bash
sudo chmod 700 /root/jumphost-backups/iptables/apply-jumphost-iptables.sh
```

---
## 6. Разбор правил без воды

### **Политика DROP**
 
```bash
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP
```
Это значит:
> Если пакет не подошёл ни под одно разрешающее правило — запретить.

Это “default deny”. Опасность: если забыть разрешить SSH, можно потерять доступ.

---
### **Loopback**

```bash
iptables -A INPUT  -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
```

`lo` — локальный интерфейс.

Нужен для локальных процессов. Без этого могут ломаться локальные сервисы:
```bash
127.0.0.1
localhost
```

---
### **ESTABLISHED,RELATED**

Это очень важное правило.
```bash
-m conntrack --ctstate ESTABLISHED,RELATED
```

Оно означает:
```txt
ESTABLISHED # пакет относится к уже существующему соединению
RELATED     # пакет связан с уже разрешённым соединением
```

Например, ты подключился по SSH. Первые пакеты — `NEW`, а ответы в рамках этой сессии — `ESTABLISHED`.

Если не разрешить `ESTABLISHED`, соединения будут ломаться. В iptables расширение `conntrack` как раз позволяет матчить состояния соединений, например `NEW`, `ESTABLISHED`, `RELATED`, `INVALID`.

---
### **SSH только с одного IP**

```bash
iptables -A INPUT -p tcp -s "$ALLOWED_SSH_IP" --dport "$SSH_PORT" ...
```

Главные места:
```bash
-s "$ALLOWED_SSH_IP"
--dport "$SSH_PORT"
```
То есть:
> Разрешить входящий TCP на порт 2222 только от `192.168.31.150`.
Если другой IP попробует подключиться к `2222`, он попадёт в DROP.

---
### **Rate limiting SSH**

```
-m limit --limit 3/min --limit-burst 3
```

Это значит:
```
--limit 3/min      — в среднем 3 новых подключения в минуту
--limit-burst 3    — короткий начальный burst до 3 подключений
```

Это не полноценная защита от всех атак, но для задания подходит: ограничивает частоту новых SSH-подключений. В iptables для таких ограничений используются match-модули вроде `limit` или более продвинутый `hashlimit`.

---
### **OUTPUT DROP**

```
iptables -P OUTPUT DROP
```
Это значит:
> Сам jump host не может ходить в интернет, если мы явно не разрешили.

Мы разрешили:
```
DNS 53
HTTP 80
HTTPS 443
приватную сеть 192.168.203.0/24
локальный тест 127.0.0.1:9000
```

----
## 7. Перед применением — проверь IP ещё раз

На jump host выполни:
```bash
ip -br a

#Вывод:
lo               UNKNOWN        127.0.0.1/8 ::1/128
enp0s3           UP             192.168.31.179/24 metric 100 fe80::a00:27ff:fe3a:55b6/64
enp0s8           UP             192.168.56.101/24 metric 1024 fe80::a00:27ff:fea7:5fd7/64
br-250476e9bee8  DOWN           172.18.0.1/16
br-5b0d1f3dca4a  DOWN           172.19.0.1/16
docker0          DOWN           172.17.0.1/16
br-afe347b988c1  DOWN           172.20.0.1/16
dop2@dop2:~$
```

Убедись, что:
```bash
192.168.31.179 # IP jump host
192.168.56.101  # приватный интерфейс
```

На Windows твой IP был в логах:
```bash
192.168.31.150
```

Если сейчас Windows IP другой — **надо заменить `ALLOWED_SSH_IP` в скрипте**.

Проверить текущий клиентский IP можно на jump host так:
```bash
who
#Либо проверить через
sudo journalctl -u ssh --since "30 minutes ago" --no-pager | grep "Accepted"
```

----
## 8. Применяем правила

Когда IP проверен, запускаем:
```bash
sudo /root/jumphost-backups/iptables/apply-jumphost-iptables.sh
```

Потом сразу:
```bash
sudo iptables -S
sudo iptables -L -n -v
```

Куда смотреть:
```bash
-P INPUT DROP
-P FORWARD DROP
-P OUTPUT DROP
```

и правила:
```bash
-s 192.168.31.150/32 -p tcp --dport 2222
--limit 3/min
```

----
## 9. Проверяем, что SSH не отрезали

Не закрывай текущую сессию. Открой новое окно PowerShell и подключись:
```bash
ssh -p 2222 dop2@192.168.31.179
```

Если вошёл — хорошо. Потом на jump host проверь:
```bash
sudo iptables -L INPUT -n -v --line-numbers
```

Куда смотреть:
```bash
ACCEPT tcp -- 192.168.31.150 0.0.0.0/0 tcp dpt:2222
```

У этого правила должны расти counters:
```bash
pkts
bytes
```

---
## 10. Проверяем, что старый порт 22 не работает

С Windows:
```bash
ssh -p 22 dop2@192.168.31.179
```

Ожидаемо:
```bash
Connection refused
#or
Connection timeout
```

---
## 11. Проверяем DNS и нужные сервисы

На jump host:
```bash
getent hosts ubuntu.com
curl -I https://ubuntu.com
```

Ожидаем:
```bash
getent hosts ubuntu.com # должен вернуть IP
curl -I https://ubuntu.com # должен вернуть HTTP headers

#Выводы: 
dop2@dop2:~$ curl -I https://ubuntu.com
HTTP/2 200
server: nginx/1.14.0 (Ubuntu)
date: Mon, 13 Jul 2026 16:49:04 GMT
content-type: text/html; charset=utf-8
content-length: 210461
content-security-policy: default-src 'self'; img-src data: blob: *; script-src-elem 'self' assets.ubuntu.com www.google-analytics.com www.googletagmanager.com dev.visualwebsiteoptimizer.com www.youtube.com asciinema.org player.vimeo.com script.crazyegg.com w.usabilla.com munchkin.marketo.net serve.nrich.ai ml314.com scout-cdn.salesloft.com snippet.maze.co www.googleadservices.com js.zi-scripts.com *.g.doubleclick.net www.google.com www.gstatic.com *.googlesyndication.com js.stripe.com d3js.org www.brighttalk.com cdnjs.cloudflare.com static.ads-twitter.com *.cdn.digitaloceanspaces.com www.redditstatic.com snap.licdn.com connect.facebook.net jspm.dev cdn.livechatinc.com api.livechatinc.com secure.livechatinc.com www.tfaforms.com api.usabilla.com *.cloudfront.net cdn.jsdelivr.net *.g.doubleclick.net extend.vimeocdn.com tracking-api.g2.com 'unsafe-inline'; font-src 'self' assets.ubuntu.com cdn.livechatinc.com secure.livechatinc.com fonts.google.com; script-src 'self' blob: *.livechatinc.com *.youtube.com *.google.com *.livechat-static.com 'unsafe-eval' 'unsafe-hashes' 'unsafe-inline'; connect-src 'self' *.googlesyndication.com www.google.com ubuntu.com analytics.google.com www.googletagmanager.com sentry.is.canonical.com www.google-analytics.com *.crazyegg.com scout.salesloft.com *.g.doubleclick.net js.zi-scripts.com *.mktoresp.com prompts.maze.co *.google-analytics.com pixel-config.reddit.com www.redditstatic.com conversions-config.reddit.com px.ads.linkedin.com ws.zoominfo.com youtube.com google.com fonts.google.com api.text.com raw.githubusercontent.com *.analytics.google.com *.g.doubleclick.net ad.doubleclick.net www.googleadservices.com www.facebook.com *.livechatinc.com *.text.com *.youtube.com *.google.com; frame-src 'self' *.doubleclick.net www.youtube.com/ asciinema.org player.vimeo.com js.stripe.com www.googletagmanager.com www.google.com www.brighttalk.com cdn.livechatinc.com secure.livechatinc.com cdn.livechat-static.com *.cloudfront.net app3.trueability.com app.trueability.com pay.stripe.com; style-src *.cloudfront.net cdn.jsdelivr.net 'self' *.livechatinc.com *.youtube.com *.google.com 'unsafe-inline'; media-src 'self' res.cloudinary.com cdn.livechatinc.com secure.livechatinc.com cdn.livechat-static.com images.zenhubusercontent.com assets.ubuntu.com *.livechatinc.com *.youtube.com *.google.com *.livechat-static.com ubuntu.com; child-src api.livechatinc.com cdn.livechatinc.com secure.livechatinc.com youtube.com google.com fonts.google.com 'self' *.livechatinc.com *.youtube.com *.google.com blob:; object-src 'self' *.livechatinc.com *.youtube.com *.google.com; frame-ancestors https://edge-billing.stripe.com https://edge-connect.stripe.com https://edge-dashboard-admin.stripe.com https://edge-dashboard.stripe.com https://edge-docs.stripe.com https://edge-marketplace.stripe.com https://edge-support.stripe.com https://billing.stripe.com https://connect.stripe.com https://dashboard-admin.stripe.com https://dashboard.stripe.com https://docs.stripe.com https://edge-support-conversations.stripe.com https://edge.stripe.com https://marketplace.stripe.com https://stripe.com https://support-admin.corp.stripe.com https://support-conversations.stripe.com https://support.stripe.com;
referrer-policy: strict-origin-when-cross-origin
cross-origin-embedder-policy: unsafe-none
cross-origin-opener-policy: same-origin-allow-popups
cross-origin-resource-policy: cross-origin
x-permitted-cross-domain-policies: none
vary: Accept-Encoding
x-clacks-overhead: GNU Terry Pratchett
permissions-policy: interest-cohort=()
cache-control: max-age=60, stale-while-revalidate=86400, stale-if-error=300
x-content-type-options: NOSNIFF
strict-transport-security: max-age=15724800
link: <https://assets.ubuntu.com>; rel=preconnect; crossorigin, <https://assets.ubuntu.com>; rel=preconnect, <https://res.cloudinary.com>; rel=preconnect
x-cache-status: HIT from content-cache-il3/1
accept-ranges: bytes

================================================================

dop2@dop2:~$ getent hosts ubuntu.com
2620:2d:4000:1::28 ubuntu.com
2620:2d:4000:1::26 ubuntu.com
2620:2d:4000:1::27 ubuntu.com

```

Почему `curl https://ubuntu.com` работает?  Потому что мы разрешили:
```bash
DNS 53
HTTPS 443
```

---
## 12. Проверяем блокировку “лишнего интернета”

Например, попробуем порт, который мы не разрешали:
```bash
timeout 5 bash -c 'cat < /dev/null > /dev/tcp/1.1.1.1/853' && echo "OPEN" || echo "BLOCKED"

#Вывод
dop2@dop2:~$ timeout 5 bash -c 'cat < /dev/null > /dev/tcp/1.1.1.1/853' && echo "OPEN" || echo "BLOCKED"
BLOCKED
```

Порт `853` — DNS-over-TLS. Мы его не разрешали.

---
## 13. Проверяем SSH-туннель

Наш прошлый учебный туннель к localhost должен работать, потому что мы специально разрешили:

```bash
127.0.0.1:9000
```

На jump host снова запусти тестовый сервис, если он не работает:
```bash
python3 -m http.server 9000 --bind 127.0.0.1 --directory ~/tunnel-test
```

В одном окне powershell Windows:
```bash
ssh -p 2222 -N -L 127.0.0.1:18080:127.0.0.1:9000 dop2@192.168.31.179
```

В другом окне PowerShell:
```bash
curl.exe http://127.0.0.1:18080
```

Ожидаем:
```bash
PS C:\Users\skame> curl.exe http://127.0.0.1:18080
SSH tunnel works
PS C:\Users\skame>
```

---
## 14. Если всё работает — отменяем авто-откат

Если SSH работает, DNS работает, tunnel работает — отменяем rollback:
```bash
sudo systemctl stop iptables-rollback.timer 2>/dev/null || true
sudo systemctl reset-failed iptables-rollback.service iptables-rollback.timer 2>/dev/null || true
```

Проверяем:
```bash
systemctl list-timers | grep iptables-rollback || echo "rollback timer is not active"
```

Ожидаем:
```bash
rollback timer is not active
```

---

## 15. Сохраняем правила для автозагрузки

Сначала проверим пакет:
```bash
dpkg -l | grep iptables-persistent
```

Если нет — установи:
```bash
sudo apt update
sudo apt install -y iptables-persistent netfilter-persistent
```

Во время установки может спросить. Можно выбрать `Yes`:
```bash
Save current IPv4 rules?
Save current IPv6 rules?
```

Потом сохраняем текущие правила:
```bash
sudo netfilter-persistent save
sudo systemctl enable netfilter-persistent
```

Проверяем файлы:
```bash
sudo ls -l /etc/iptables/
sudo cat /etc/iptables/rules.v4 | head -n 40
```

На Ubuntu пакет `iptables-persistent` обычно использует `netfilter-persistent`, а правила IPv4 сохраняются в `/etc/iptables/rules.v4`.

## 16. Проверка по iptables

### 16.1 Проверка iptables

У нас сейчас вот так:
```
-P INPUT DROP
-P FORWARD DROP
-P OUTPUT DROP
```

Надо обратить внимание сюда:
```
DROP
```
Это значит:
> Всё, что явно не разрешено правилами, запрещается.

Это правильная модель для jump host.

---

### 16.2 SSH разрешён только с твоего IP

У тебя есть правило:
```
-A INPUT -s 192.168.31.150/32 -p tcp --dport 2222 ... -j ACCEPT
```

Главные места:
```bash
-s 192.168.31.150/32
--dport 2222
-j ACCEPT
```
Это значит:
> Разрешить новые SSH-подключения на порт `2222` только с IP `192.168.31.150`.

И journal подтверждает, что именно с этого IP ты заходишь:
```
Accepted password for dop2 from 192.168.31.150
```

Значит `ALLOWED_SSH_IP` выбран правильно.

---
### 16.3 Rate limit тоже стоит

Правило:
```bash
-m limit --limit 3/min --limit-burst 3
```
Означает:
> Разрешить примерно 3 новых SSH-подключения в минуту.

В `iptables -L -n -v` видно:
```bash
2   120 ACCEPT tcp ... 192.168.31.150 ... tcp dpt:2222 ... limit: avg 3/min burst 3
```

Главное:
```bash
pkts 2
```

Счётчик уже вырос. Значит правило реально сработало.

---

### 16.4 Почему `who` пустой

Ввел и ничего не произошло:
```bash
who
```
Это не страшно. `who` читает записи из `utmp`, и не все SSH-сессии/окружения всегда отображаются там так, как ожидаешь.

Для нашей задачи лучше ориентироваться на:
```
sudo journalctl -u ssh --since "30 minutes ago" --no-pager | grep "Accepted"
```

У тебя он показывает входы нормально:

```
Accepted publickey for dop2 from 192.168.31.150
Accepted password for dop2 from 192.168.31.150
```

Это надёжнее для проверки SSH-входов.

---
### 16.5 OUTPUT-правила тоже работают

На данный момент у нас. То есть исходящий трафик запрещён по умолчанию.:
```bash
-P OUTPUT DROP
```

Но разрешены:
```bash
udp/tcp 53 — DNS
tcp 80 — HTTP
tcp 443 — HTTPS
tcp в 192.168.56.0/24 — приватная сеть
127.0.0.1:9000 — учебный tunnel-test
```

Это соответствует логике задания:
```txt
заблокировать исходящий интернет кроме DNS/нужных сервисов
разрешить forwarding только в приватную сеть
```

Но важный нюанс: правило на `127.0.0.1:9000` в счётчиках может быть `0`, потому что выше стоит:
```
-A OUTPUT -o lo -j ACCEPT
```

То есть трафик на localhost ловится раньше правилом loopback, а до правила `127.0.0.1:9000` может просто не доходить. Это нормально.

## 17. Сохраняем iptables правила через `netfilter-persistent`
### 17.1. Проверяем, установлен ли `netfilter-persistent`

Выполним:

```bash
#ПРоверка установлен ли необходимый модуль
dpkg -l | grep -E 'iptables-persistent|netfilter-persistent'
```

Если в выводе есть что-то вроде, значит пакеты уже стоят.:
```bash
iptables-persistent
netfilter-persistent
```

Если ничего нет — устанавливаем:
```bash
sudo apt update
sudo apt install -y iptables-persistent netfilter-persistent
```

Во время установки может спросить:
```bash
#Спросят
Save current IPv4 rules?
Save current IPv6 rules?
#Выбрать
Yes
```

---
### 17.2. Сохраняем текущие IPv4-правила

Выполним:
```bash
sudo netfilter-persistent save
```

Что делает команда:
```bash
netfilter-persistent — сервис для сохранения/загрузки firewall-правил
save — сохранить текущие активные правила
```

Фактически он делает примерно это:
```bash
iptables-save > /etc/iptables/rules.v4
```

---
### 17.3. Проверяем, что файл появился

```bash
sudo ls -lh /etc/iptables/

#Вывод
dop2@dop2:~$ sudo ls -lh /etc/iptables/
total 8.0K
-rw-r----- 1 root root 1.8K Jul 13 17:34 rules.v4
-rw-r----- 1 root root  849 Jul 13 17:34 rules.v6

#Главное сейчас:
-rw-r----- 1 root root 1.8K Jul 13 17:34 rules.v4
```

---
### 17.4. Проверяем содержимое сохранённых правил

```bash
sudo head -n 40 /etc/iptables/rules.v4

#Вывод:
dop2@dop2:~$ sudo head -n 40 /etc/iptables/rules.v4
# Generated by iptables-save v1.8.11 (nf_tables) on Mon Jul 13 17:34:39 2026
*filter
:INPUT DROP [638:71169]
:FORWARD DROP [0:0]
:OUTPUT DROP [633:51688]
-A INPUT -i lo -j ACCEPT
-A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A INPUT -m conntrack --ctstate INVALID -j DROP
-A INPUT -s 192.168.31.150/32 -p tcp -m tcp --dport 2222 -m conntrack --ctstate NEW -m limit --limit 3/min --limit-burst 3 -j ACCEPT
-A INPUT -p tcp -m tcp --dport 2222 -m limit --limit 5/min -j LOG --log-prefix "IPTABLES SSH DROP: "
-A INPUT -p tcp -m tcp --dport 2222 -j DROP
-A OUTPUT -o lo -j ACCEPT
-A OUTPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A OUTPUT -m conntrack --ctstate INVALID -j DROP
-A OUTPUT -p udp -m udp --dport 53 -j ACCEPT
-A OUTPUT -p tcp -m tcp --dport 53 -j ACCEPT
-A OUTPUT -p tcp -m tcp --dport 80 -j ACCEPT
-A OUTPUT -p tcp -m tcp --dport 443 -j ACCEPT
-A OUTPUT -d 192.168.56.0/24 -p tcp -j ACCEPT
-A OUTPUT -d 127.0.0.1/32 -p tcp -m tcp --dport 9000 -j ACCEPT
-A OUTPUT -m limit --limit 5/min -j LOG --log-prefix "IPTABLES OUTPUT DROP: "
COMMIT
# Completed on Mon Jul 13 17:34:39 2026
# Generated by iptables-save v1.8.11 (nf_tables) on Mon Jul 13 17:34:39 2026
*nat
:PREROUTING ACCEPT [8630:952764]
:INPUT ACCEPT [7989:880258]
:OUTPUT ACCEPT [8750:696669]
:POSTROUTING ACCEPT [8117:644981]
:DOCKER - [0:0]
-A PREROUTING -m addrtype --dst-type LOCAL -j DOCKER
-A OUTPUT ! -d 127.0.0.0/8 -m addrtype --dst-type LOCAL -j DOCKER
-A POSTROUTING -s 172.17.0.0/16 ! -o docker0 -j MASQUERADE
-A POSTROUTING -s 172.20.0.0/16 ! -o br-afe347b988c1 -j MASQUERADE
-A POSTROUTING -s 172.19.0.0/16 ! -o br-5b0d1f3dca4a -j MASQUERADE
-A POSTROUTING -s 172.18.0.0/16 ! -o br-250476e9bee8 -j MASQUERADE
COMMIT
# Completed on Mon Jul 13 17:34:39 2026
```

Главные места:
```bash
:INPUT DROP
:FORWARD DROP
:OUTPUT DROP
```
и:
```bash
--dport 2222
192.168.31.150
192.168.56.0/24
```

Это значит, что сохранились именно наши jump host правила.

---
### 17.5. Включаем автозагрузку сервиса

```bash
#Включаем сервис
sudo systemctl enable netfilter-persistent

#Проверяем статус
systemctl status netfilter-persistent --no-pager

#Вывод:
dop2@dop2:~$ systemctl status netfilter-persistent --no-pager
● netfilter-persistent.service - netfilter persistent configuration
     Loaded: loaded (/usr/lib/systemd/system/netfilter-persistent.service; enabled; preset: enabled)
    Drop-In: /usr/lib/systemd/system/netfilter-persistent.service.d
             └─iptables.conf
     Active: active (exited) since Mon 2026-07-13 05:59:52 UTC; 11h ago
 Invocation: f7a8f94815d34a11a3313f5a84553941
       Docs: man:netfilter-persistent(8)
   Main PID: 813 (code=exited, status=0/SUCCESS)
   Mem peak: 2.5M
        CPU: 12ms

Warning: some journal files were not opened due to insufficient permissions.
```

Нас интересует не обязательно `active running`, потому что это oneshot-сервис. Главное, чтобы было что-то вроде:
```
Loaded: loaded
enabled
```

---
### 17.6. Проверяем, что правила можно загрузить вручную

Осторожная проверка:
```bash
sudo netfilter-persistent reload
```

После этого сразу:
```bash
#ПРоверяем правила
sudo iptables -S

#Вывод:
dop2@dop2:~$ sudo iptables -S
-P INPUT DROP
-P FORWARD DROP
-P OUTPUT DROP
-A INPUT -i lo -j ACCEPT
-A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A INPUT -m conntrack --ctstate INVALID -j DROP
-A INPUT -s 192.168.31.150/32 -p tcp -m tcp --dport 2222 -m conntrack --ctstate NEW -m limit --limit 3/min --limit-burst 3 -j ACCEPT
-A INPUT -p tcp -m tcp --dport 2222 -m limit --limit 5/min -j LOG --log-prefix "IPTABLES SSH DROP: "
-A INPUT -p tcp -m tcp --dport 2222 -j DROP
-A OUTPUT -o lo -j ACCEPT
-A OUTPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A OUTPUT -m conntrack --ctstate INVALID -j DROP
-A OUTPUT -p udp -m udp --dport 53 -j ACCEPT
-A OUTPUT -p tcp -m tcp --dport 53 -j ACCEPT
-A OUTPUT -p tcp -m tcp --dport 80 -j ACCEPT
-A OUTPUT -p tcp -m tcp --dport 443 -j ACCEPT
-A OUTPUT -d 192.168.56.0/24 -p tcp -j ACCEPT
-A OUTPUT -d 127.0.0.1/32 -p tcp -m tcp --dport 9000 -j ACCEPT
-A OUTPUT -m limit --limit 5/min -j LOG --log-prefix "IPTABLES OUTPUT DROP: "
```

---

### 17.7. Проверяем SSH после reload

Из нового окна PowerShell:

```
ssh -p 2222 dop2@192.168.31.179
```

Если вход работает — сохранённые правила не сломали доступ.

---
### 17.8. Если у тебя висит rollback timer

Проверь:
```bash
systemctl list-timers | grep iptables-rollback
```

Если он есть, и ты уже проверил SSH, можно отменить:
```bash
sudo systemctl stop iptables-rollback-test.timer iptables-rollback.service 2>/dev/null || true
sudo systemctl reset-failed iptables-rollback-test.timer iptables-rollback.service 2>/dev/null || true
```

Проверка:
```bash
systemctl list-timers | grep iptables-rollback || echo "rollback timer is not active"
```


# 5. 📱 Настройка 2FA (Google Authenticator)

## 0. Очень важное перед началом

**Не закрывай текущую SSH-сессию.**

2FA настраивается через PAM и SSH. Если ошибиться в `/etc/pam.d/sshd` или `sshd_config`, можно временно потерять вход.

Работать будем безопасно:

```
1. Сначала backup
2. Потом проверка времени
3. Потом установка PAM-модуля
4. Потом включаем 2FA мягко через nullok
5. Инициализируем 2FA только для jump-test
6. Проверяем вход jump-test
7. Потом решаем, включать ли строго для всех
```

---

## 1. Важный момент: 2FA зависит от времени

Google Authenticator обычно использует **TOTP** — одноразовые коды, зависящие от времени. Сам проект `google-authenticator-libpam` пишет, что поддерживает HOTP и TOTP, а TOTP описан в RFC 6238.

Поэтому сервер и телефон должны иметь примерно одинаковое время.

У тебя сейчас firewall `OUTPUT DROP`, и мы разрешали DNS/HTTP/HTTPS, но **NTP UDP 123** не разрешали. Для 2FA лучше разрешить исходящую синхронизацию времени.

Проверь:

```
timedatectl
```

Куда смотреть:

```
System clock synchronized: yes
NTP service: active
```

Если там `yes` и `active` — хорошо.

---
### 1.1 Если System clock synchronized: no, то:

Нужно синхронизировать время для 2FA без этого шага мы не сможем настроить это. В Ubuntu сейчас документирует `chrony` как способ синхронизации времени, а `timedatectl/timesyncd` — как запасной вариант.

```bash
#Проверяем установлен ли chrony:
dpkg -l | grep chrony

#ПРоверяем статус нашего сервиса
systemctl status chrony --no-pager

#Вывод:

dop2@dop2:~$ dpkg -l | grep chrony
ii  chrony                                  4.8-2ubuntu1                               amd64        Versatile implementation of the Network Time Protocol

======================================================================

dop2@dop2:~$ systemctl status chrony --no-pager
● chrony.service - chrony, an NTP client/server
     Loaded: loaded (/usr/lib/systemd/system/chrony.service; enabled; preset: enabled)
     Active: active (running) since Mon 2026-07-13 05:59:57 UTC; 14h ago
 Invocation: ce437df2e29f4d669182bf53fce34814
       Docs: man:chronyd(8)
             man:chronyc(1)
             man:chrony.conf(5)
   Main PID: 1345 (chronyd-starter)
      Tasks: 3 (limit: 3971)
     Memory: 7M (peak: 7.8M)
        CPU: 1.078s
     CGroup: /system.slice/chrony.service
             ├─1345 /bin/sh /usr/lib/systemd/scripts/chronyd-starter.sh -n -F 1
             ├─1427 /usr/sbin/chronyd -n -F 1
             └─1531 /usr/sbin/chronyd -n -F 1
             

#Если нет просто устанавливаем
sudo apt update
sudo apt install -y chrony
```

----
### 1.2 Разрешаем NTP в iptables

Добавляем правило:
```bash
sudo iptables -I OUTPUT 8 -p udp --dport 123 -j ACCEPT
```

Почему `OUTPUT`? Потому что сервер сам выходит к NTP-серверу:
```
jump host → NTP server
```

Это исходящее соединение, значит цепочка:
```
OUTPUT
```

Проверяем:
```bash
sudo iptables -L OUTPUT -n -v --line-numbers | grep 'dpt:123'
```

Должно быть что-то вроде:
```
ACCEPT udp -- 0.0.0.0/0 0.0.0.0/0 udp dpt:123
```

Потом сохраняем:
```bash
sudo netfilter-persistent save
```

---
### 1.3 Перезапускаем/Запускаем Chrony

```bash
sudo systemctl enable --now chrony
sudo systemctl restart chrony
```

Проверяем:
```bash
#Смотрим статус
systemctl status chrony --no-pager

#Нужно искать
Active: active (running)
```

### 1.4 Проверяем синхронизацию через chrony

```bash
#Запускаем
chronyc tracking

#Вывод
dop2@dop2:~$ chronyc tracking
Reference ID    : 53F3449D (83.243.68.157)
Stratum         : 3
Ref time (UTC)  : Mon Jul 13 21:08:31 2026
System time     : 0.000107257 seconds slow of NTP time
Last offset     : +0.001571607 seconds
RMS offset      : 0.001571607 seconds
Frequency       : 1.174 ppm slow
Residual freq   : +51.478 ppm
Skew            : 2.283 ppm
Root delay      : 0.028632173 seconds
Root dispersion : 0.002275033 seconds
Update interval : 0.0 seconds
Leap status     : Normal
```

Хорошие признаки:
```
Leap status     : Normal
Reference ID    : ...
System time     : ...
```

Ещё:
```
chronyc sources -v
```

Смотреть надо на строки с `^*` или `^+`. Пример:
```
^* time.cloudflare.com ...
```

Значение:
```
^* — выбранный текущий источник времени
^+ — хороший кандидат
```

### 1.5 Проверка `timedatectl`

После chrony проверь:
```bash
timedatectl
```

Нужно добиться:
```bash
System clock synchronized: yes
NTP service: active
```

Иногда `chrony` нужно немного времени — подожди 30–60 секунд и повтори:
```bash
timedatectl
chronyc tracking
```

---
## 2. Backup перед изменениями SSH/PAM

Необходимо выполнить
```bash
sudo mkdir -p /home/dop2/jumphost-backups/2fa

sudo cp -a /etc/pam.d/sshd /home/dop2/jumphost-backups/2fa/sshd.pam.backup.$(date +%F-%H%M%S)

sudo cp -a /etc/ssh/sshd_config /home/dop2/jumphost-backups/2fa/sshd_config.backup.$(date +%F-%H%M%S)

sudo cp -a /etc/ssh/sshd_config.d /home/dop2/jumphost-backups/2fa/sshd_config.d.backup.$(date +%F-%H%M%S)
```

Зачем:
```txt
если PAM/SSH сломается, мы сможем быстро вернуть старые файлы
```

---
## 3. Устанавливаем Google Authenticator PAM module

Проверь:
```bash
dpkg -l | grep -E 'libpam-google-authenticator|qrencode'
```

Если пакетов нет:
```bash
sudo apt update
sudo apt install -y libpam-google-authenticator qrencode
```

Ubuntu tutorial устанавливает именно пакет `libpam-google-authenticator`.

Проверка:
```bash
which google-authenticator
ls -l /lib/*/security/pam_google_authenticator.so
```

Ожидаем:
```bash
/usr/bin/google-authenticator
pam_google_authenticator.so
```

---
## 4. Включаем keyboard-interactive в SSH

В старых инструкциях это называется:
```bash
ChallengeResponseAuthentication yes
```

Но в современных OpenSSH правильное имя. В man page OpenSSH прямо указано, что `ChallengeResponseAuthentication` — deprecated alias для `KbdInteractiveAuthentication`.:
```bash
KbdInteractiveAuthentication yes
```

Открываем наш jump host SSH config:
```bash
sudo nano /etc/ssh/sshd_config.d/99-jumphost.conf
```

Найди строку:
```bash
KbdInteractiveAuthentication no
```

Если есть — замени на:
```bash
KbdInteractiveAuthentication yes
```

Если строки нет — добавь:
```bash
KbdInteractiveAuthentication yes
```

Также убедись, что есть:
```bash
UsePAM yes
```

И пока оставляем:
```bash
PasswordAuthentication yes
```

На учебном этапе так проще: сначала доказываем, что 2FA работает. Потом можно ужесточать.

---
## 5. Проверяем SSH-конфиг

```bash
sudo sshd -t #Если вывода нет — хорошо.
```

Потом:
```bash
sudo sshd -T | grep -E '^usepam|^kbdinteractiveauthentication|^passwordauthentication|^authenticationmethods'
```

Ожидаем:
```bash
usepam yes
kbdinteractiveauthentication yes
passwordauthentication yes
```

---
## 6. Подключаем PAM-модуль Google Authenticator

Открываем:
```bash
sudo nano /etc/pam.d/sshd
```

В секции `auth` добавь строку **после**:
```
@include common-auth
```

Добавь:
```
auth required pam_google_authenticator.so nullok
```

То есть начало файла должно быть примерно так:
```
# PAM configuration for the Secure Shell service

@include common-auth
auth required pam_google_authenticator.so nullok
```

---
### Почему пока `nullok`

Строка, означает, если у пользователя есть ~/.google_authenticator — требовать 2FA если файла нет — пока пустить без 2FA:
```bash
auth required pam_google_authenticator.so nullok
```

Это безопасный режим внедрения. Google Authenticator PAM README прямо описывает `nullok` как вариант для rollout-периода, когда ещё не все пользователи создали secret-файл. Если сразу поставить без `nullok`, то можно случайно заблокировать всех пользователей, у которых ещё нет `~/.google_authenticator`:
```
auth required pam_google_authenticator.so
```

---
## 7. Проверяем PAM-файл

Покажи важные строки:
```bash
grep -nE 'common-auth|pam_google_authenticator|pam_exec' /etc/pam.d/sshd
```

Ожидаем увидеть примерно. Строка `pam_exec` для login alert должна остаться. Мы её не удаляем:
```bash
@include common-auth
auth required pam_google_authenticator.so nullok
session optional pam_exec.so seteuid /usr/local/bin/ssh-login-alert.sh
```

---
## 8. Перезапускаем SSH

Так как у тебя используется `ssh.socket`, делаем так:
```bash
sudo systemctl restart ssh.socket
sudo systemctl restart ssh
```

Проверяем:
```bash
sudo systemctl status ssh --no-pager
sudo systemctl status ssh.socket --no-pager

#Вывод:

dop2@dop2:~$ sudo systemctl status ssh --no-pager
● ssh.service - OpenBSD Secure Shell server
     Loaded: loaded (/usr/lib/systemd/system/ssh.service; enabled; preset: enabled)
     Active: active (running) since Mon 2026-07-13 21:46:03 UTC; 1s ago
 Invocation: 7069ec4ee03b4d468b431cb0fdfcde41
TriggeredBy: ● ssh.socket
       Docs: man:sshd(8)
             man:sshd_config(5)
    Process: 12239 ExecStartPre=/usr/sbin/sshd -t (code=exited, status=0/SUCCESS)
   Main PID: 12242 (sshd)
      Tasks: 1 (limit: 3971)
     Memory: 1.5M (peak: 2.4M)
        CPU: 15ms
     CGroup: /system.slice/ssh.service
             └─12242 "sshd: /usr/sbin/sshd -D [listener] 0 of 10-100 startups"
             
=====================================================================

dop2@dop2:~$ sudo systemctl status ssh.socket --no-pager
● ssh.socket - OpenBSD Secure Shell server socket
     Loaded: loaded (/usr/lib/systemd/system/ssh.socket; enabled; preset: enabled)
    Drop-In: /run/systemd/generator/ssh.socket.d
             └─addresses.conf
     Active: active (running) since Mon 2026-07-13 21:45:48 UTC; 23s ago
 Invocation: c9017cd1f23a4482b3eba3185538a91a
   Triggers: ● ssh.service
     Listen: 0.0.0.0:2222 (Stream)
             [::]:2222 (Stream)
      Tasks: 0 (limit: 3971)
     Memory: 12K (peak: 512K)
        CPU: 580us
     CGroup: /system.slice/ssh.socket

Jul 13 21:45:48 dop2 systemd[1]: Listening on ssh.socket - OpenBSD Secure Shell server socket.
```

---
## 9. Инициализируем 2FA для тестового пользователя `jump-test`

Важно: secret-файл должен появиться в домашней директории именно `jump-test`:
```bash
/home/jump-test/.google_authenticator
```

Запускаем команду от имени `jump-test`:
```bash
sudo -u jump-test google-authenticator
```

Он задаст вопросы. Рекомендованные ответы для учебного задания:
```
Do you want authentication tokens to be time-based? y

Do you want me to update your "/home/jump-test/.google_authenticator" file? y

Do you want to disallow multiple uses of the same authentication token? y

By default, tokens are good for 30 seconds...
Do you want to increase the original generation time limit? n

Do you want to enable rate-limiting? y
```

Ubuntu tutorial рекомендует time-based tokens, обновить `.google_authenticator`, запретить повторное использование, не увеличивать окно времени и включить rate-limiting.

---

## 10. Что обязательно сохранить

После запуска `google-authenticator` ты увидишь:
```
QR-код
secret key
emergency scratch codes #Важно сохранить
```
Не публикуй QR-код и secret key в чат.

---
## 11. Проверяем файл secret

После инициализации:
```bash
sudo ls -l /home/jump-test/.google_authenticator
```

Ожидаем права как указаны ниже или похожие строгие права.:
```bash
-r-------- 1 jump-test jump-test ...
```

Главное:
```
владелец jump-test
права не слишком открытые
```

PAM-модуль по умолчанию строго проверяет владельца и права secret-файла; в README есть отдельные предупреждения про owner и permissions.

---
## 12. Проверяем вход `jump-test`

Не закрывая текущую SSH-сессию, открой новое окно PowerShell:
```bash
ssh -p 2222 jump-test@192.168.31.179
```

Ожидаем примерно такую последовательность:
```bash
jump-test@192.168.31.179's password:
Verification code:
```

или:
```bash
Password:
Verification code:
```

Вводишь пароль `jump-test`, потом код из приложения.

Если вошёл — 2FA работает.

---
## 13. Проверяем, что `dop2` пока не заблокирован

Так как мы поставили `nullok`, у `dop2`, если нет файла, 2FA пока не должна требоваться:
```
/home/dop2/.google_authenticator
```

Проверь в новом окне, Если входит как раньше — хорошо.:
```
ssh -p 2222 dop2@192.168.31.179
```

---
## 14. Проверяем логи

После попытки входа:
```bash
#Смотрим системный журнал за последние 10 минут
sudo journalctl -u ssh --since "10 minutes ago" --no-pager

#Вывод
dop2@dop2:~$ sudo journalctl -u ssh --since "10 minutes ago" --no-pager
Jul 13 21:57:09 dop2 sshd(pam_google_auth)[12337]: Invalid verification code for jump-test
Jul 13 21:57:12 dop2 sshd-session[12335]: error: PAM: Authentication failure for jump-test from 192.168.31.150
Jul 13 21:58:56 dop2 sshd[12242]: Timeout before authentication for connection from 192.168.31.150 to 192.168.31.179, pid = 12335
Jul 13 22:00:28 dop2 sshd-session[12351]: Accepted publickey for dop2 from 192.168.31.150 port 57725 ssh2: ED25519 SHA256:IdUUzybnL5AHpL6BtM6HYxV6FWNI6jNrGLqV+DxnZQ4
Jul 13 22:00:28 dop2 sshd-session[12351]: pam_unix(sshd:session): session opened for user dop2(uid=1000) by dop2(uid=0)
Jul 13 22:02:11 dop2 sshd(pam_google_auth)[12493]: Accepted google_authenticator for jump-test
Jul 13 22:02:11 dop2 sshd-session[12491]: Accepted keyboard-interactive/pam for jump-test from 192.168.31.150 port 58567 ssh2
Jul 13 22:02:11 dop2 sshd-session[12491]: pam_unix(sshd:session): session opened for user jump-test(uid=1002) by jump-test(uid=0)
```

И наш alert-log:

```bash
#Смотрим алерты по ssh соединенибю 
sudo tail -n 30 /var/log/ssh-login-alerts.log

#Вывод:
dop2@dop2:~$ sudo tail -n 30 /var/log/ssh-login-alerts.log
========================================
SSH LOGIN ALERT
Time: 2026-07-13T21:12:00+00:00
User: dop2
Remote host: 192.168.31.150
Service: sshd
TTY: ssh
Server: dop2
========================================

========================================
SSH LOGIN ALERT
Time: 2026-07-13T22:00:29+00:00
User: dop2
Remote host: 192.168.31.150
Service: sshd
TTY: ssh
Server: dop2
========================================

========================================
SSH LOGIN ALERT
Time: 2026-07-13T22:02:12+00:00
User: jump-test
Remote host: 192.168.31.150
Service: sshd
TTY: ssh
Server: dop2
========================================
```

Также можно проверить, что auditd видит команды:
```bash
#ПРоверяем логирование auditd
sudo ausearch -k user-commands -i | grep -E 'google-authenticator|ssh|sudo' | tail -n 30

#Вывод 
dop2@dop2:~$ sudo ausearch -k user-commands -i | grep -E 'google-authenticator|ssh|sudo' | tail -n 30
type=PROCTITLE msg=audit(07/13/2026 22:02:12.373:5996) : proctitle=/usr/bin/env bash /usr/local/bin/ssh-login-alert.sh
type=PATH msg=audit(07/13/2026 22:02:12.373:5996) : item=0 name=/usr/local/bin/ssh-login-alert.sh inode=1844043 dev=08:02 mode=file,755 ouid=root ogid=root rdev=00:00 nametype=NORMAL cap_fp=none cap_fi=none cap_fe=0 cap_fver=0 cap_frootid=0
type=EXECVE msg=audit(07/13/2026 22:02:12.373:5996) : argc=3 a0=/usr/bin/env a1=bash a2=/usr/local/bin/ssh-login-alert.sh
type=SYSCALL msg=audit(07/13/2026 22:02:12.373:5996) : arch=x86_64 syscall=execve success=yes exit=0 a0=0x57b052e2c8e8 a1=0x57b052e566f0 a2=0x57b052e5c9d0 a3=0xffffffff items=3 ppid=12491 pid=12573 auid=jump-test uid=root gid=root euid=root suid=root fsuid=root egid=root sgid=root fsgid=root tty=(none) ses=46 comm=ssh-login-alert exe=/usr/lib/cargo/bin/coreutils/env subj=unconfined key=user-commands
type=PROCTITLE msg=audit(07/13/2026 22:02:12.375:5997) : proctitle=/usr/bin/env bash /usr/local/bin/ssh-login-alert.sh
type=SYSCALL msg=audit(07/13/2026 22:02:12.375:5997) : arch=x86_64 syscall=execve success=no exit=ENOENT(No such file or directory) a0=0x7ffee9cbdca0 a1=0x59dc7ed81cd0 a2=0x7ffee9cbe738 a3=0x59dc7ed81cf0 items=1 ppid=12491 pid=12573 auid=jump-test uid=root gid=root euid=root suid=root fsuid=root egid=root sgid=root fsgid=root tty=(none) ses=46 comm=ssh-login-alert exe=/usr/lib/cargo/bin/coreutils/env subj=unconfined key=user-commands
type=PROCTITLE msg=audit(07/13/2026 22:02:12.375:5998) : proctitle=/usr/bin/env bash /usr/local/bin/ssh-login-alert.sh
type=SYSCALL msg=audit(07/13/2026 22:02:12.375:5998) : arch=x86_64 syscall=execve success=no exit=ENOENT(No such file or directory) a0=0x7ffee9cbdca0 a1=0x59dc7ed81cd0 a2=0x7ffee9cbe738 a3=0x59dc7ed81cf0 items=1 ppid=12491 pid=12573 auid=jump-test uid=root gid=root euid=root suid=root fsuid=root egid=root sgid=root fsgid=root tty=(none) ses=46 comm=ssh-login-alert exe=/usr/lib/cargo/bin/coreutils/env subj=unconfined key=user-commands
type=PROCTITLE msg=audit(07/13/2026 22:02:12.375:5999) : proctitle=/usr/bin/env bash /usr/local/bin/ssh-login-alert.sh
type=SYSCALL msg=audit(07/13/2026 22:02:12.375:5999) : arch=x86_64 syscall=execve success=no exit=ENOENT(No such file or directory) a0=0x7ffee9cbdca0 a1=0x59dc7ed81cd0 a2=0x7ffee9cbe738 a3=0x59dc7ed81cf0 items=1 ppid=12491 pid=12573 auid=jump-test uid=root gid=root euid=root suid=root fsuid=root egid=root sgid=root fsgid=root tty=(none) ses=46 comm=ssh-login-alert exe=/usr/lib/cargo/bin/coreutils/env subj=unconfined key=user-commands
type=PROCTITLE msg=audit(07/13/2026 22:02:12.375:6000) : proctitle=/usr/bin/env bash /usr/local/bin/ssh-login-alert.sh
type=EXECVE msg=audit(07/13/2026 22:02:12.375:6000) : argc=2 a0=bash a1=/usr/local/bin/ssh-login-alert.sh
type=PROCTITLE msg=audit(07/13/2026 22:04:54.374:6030) : proctitle=sudo journalctl -u ssh --since 10 minutes ago --no-pager
type=PATH msg=audit(07/13/2026 22:04:54.374:6030) : item=0 name=/usr/bin/sudo inode=1707389 dev=08:02 mode=file,suid,755 ouid=root ogid=root rdev=00:00 nametype=NORMAL cap_fp=none cap_fi=none cap_fe=0 cap_fver=0 cap_frootid=0
type=EXECVE msg=audit(07/13/2026 22:04:54.374:6030) : argc=7 a0=sudo a1=journalctl a2=-u a3=ssh a4=--since a5=10 minutes ago a6=--no-pager
type=SYSCALL msg=audit(07/13/2026 22:04:54.374:6030) : arch=x86_64 syscall=execve success=yes exit=0 a0=0x5741aa210590 a1=0x5741aa210fd0 a2=0x5741aa1cd4a0 a3=0x51 items=2 ppid=12435 pid=12617 auid=dop2 uid=dop2 gid=dop2 euid=root suid=root fsuid=root egid=dop2 sgid=dop2 fsgid=dop2 tty=pts0 ses=45 comm=sudo exe=/usr/lib/cargo/bin/sudo subj=unconfined key=user-commands
type=PROCTITLE msg=audit(07/13/2026 22:04:54.379:6035) : proctitle=journalctl -u ssh --since 10 minutes ago --no-pager
type=EXECVE msg=audit(07/13/2026 22:04:54.379:6035) : argc=6 a0=journalctl a1=-u a2=ssh a3=--since a4=10 minutes ago a5=--no-pager
type=PROCTITLE msg=audit(07/13/2026 22:05:48.848:6039) : proctitle=sudo tail -n 30 /var/log/ssh-login-alerts.log
type=PATH msg=audit(07/13/2026 22:05:48.848:6039) : item=0 name=/usr/bin/sudo inode=1707389 dev=08:02 mode=file,suid,755 ouid=root ogid=root rdev=00:00 nametype=NORMAL cap_fp=none cap_fi=none cap_fe=0 cap_fver=0 cap_frootid=0
type=EXECVE msg=audit(07/13/2026 22:05:48.848:6039) : argc=5 a0=sudo a1=tail a2=-n a3=30 a4=/var/log/ssh-login-alerts.log
type=SYSCALL msg=audit(07/13/2026 22:05:48.848:6039) : arch=x86_64 syscall=execve success=yes exit=0 a0=0x5741aa2111f0 a1=0x5741aa210550 a2=0x5741aa1cd4a0 a3=0x40 items=2 ppid=12435 pid=12631 auid=dop2 uid=dop2 gid=dop2 euid=root suid=root fsuid=root egid=dop2 sgid=dop2 fsgid=dop2 tty=pts0 ses=45 comm=sudo exe=/usr/lib/cargo/bin/sudo subj=unconfined key=user-commands
type=PROCTITLE msg=audit(07/13/2026 22:05:48.853:6044) : proctitle=tail -n 30 /var/log/ssh-login-alerts.log
type=EXECVE msg=audit(07/13/2026 22:05:48.853:6044) : argc=4 a0=tail a1=-n a2=30 a3=/var/log/ssh-login-alerts.log
type=PROCTITLE msg=audit(07/13/2026 22:06:47.231:6048) : proctitle=grep --color=auto -E google-authenticator|ssh|sudo
type=EXECVE msg=audit(07/13/2026 22:06:47.231:6048) : argc=4 a0=grep a1=--color=auto a2=-E a3=google-authenticator|ssh|sudo
type=PROCTITLE msg=audit(07/13/2026 22:06:47.231:6050) : proctitle=sudo ausearch -k user-commands -i
type=PATH msg=audit(07/13/2026 22:06:47.231:6050) : item=0 name=/usr/bin/sudo inode=1707389 dev=08:02 mode=file,suid,755 ouid=root ogid=root rdev=00:00 nametype=NORMAL cap_fp=none cap_fi=none cap_fe=0 cap_fver=0 cap_frootid=0
type=EXECVE msg=audit(07/13/2026 22:06:47.231:6050) : argc=5 a0=sudo a1=ausearch a2=-k a3=user-commands a4=-i
type=SYSCALL msg=audit(07/13/2026 22:06:47.231:6050) : arch=x86_64 syscall=execve success=yes exit=0 a0=0x5741aa0e4540 a1=0x5741aa20fe40 a2=0x5741aa1cd4a0 a3=0x8 items=2 ppid=12435 pid=12645 auid=dop2 uid=dop2 gid=dop2 euid=root suid=root fsuid=root egid=dop2 sgid=dop2 fsgid=dop2 tty=pts0 ses=45 comm=sudo exe=/usr/lib/cargo/bin/sudo subj=unconfined key=user-commands
```

---

## 15. Когда всё заработает — можно ужесточить

После того как ты убедишься, что `jump-test` с 2FA входит, есть два варианта.

### Вариант A — учебный, безопасный

Оставить и тогда 2FA требуется только тем пользователям, у кого есть `~/.google_authenticator`.:
```
auth required pam_google_authenticator.so nullok
```

### Вариант B — строгий

Убрать `nullok`:
```
auth required pam_google_authenticator.so
```

Тогда **каждый SSH-пользователь обязан иметь 2FA secret-файл**. Перед строгим режимом нужно инициализировать 2FA для `dop2` тоже:
```
google-authenticator
```

Но это можно сделать только после проверки на `jump-test`.

---

## Команды сейчас по порядку

```
timedatectl
sudo iptables -L OUTPUT -n -v --line-numbers
```

Если нет UDP 123 до LOG:
```bash
sudo iptables -I OUTPUT 10 -p udp --dport 123 -j ACCEPT
sudo netfilter-persistent save
```

Backup:
```bash
sudo mkdir -p /home/dop2/jumphost-backups/2fa
sudo cp -a /etc/pam.d/sshd /home/dop2/jumphost-backups/2fa/sshd.pam.backup.$(date +%F-%H%M%S)
sudo cp -a /etc/ssh/sshd_config /home/dop2/jumphost-backups/2fa/sshd_config.backup.$(date +%F-%H%M%S)
sudo cp -a /etc/ssh/sshd_config.d /home/dop2/jumphost-backups/2fa/sshd_config.d.backup.$(date +%F-%H%M%S)
```

Install/check:
```bash
sudo apt install -y libpam-google-authenticator qrencode
which google-authenticator
```

SSH config:
```bash
sudo nano /etc/ssh/sshd_config.d/99-jumphost.conf
```

Должно быть:
```bash
UsePAM yes
KbdInteractiveAuthentication yes
```

PAM:
```bash
sudo nano /etc/pam.d/sshd
```

Добавить после `@include common-auth`:
```bash
auth required pam_google_authenticator.so nullok
```

Проверка:
```bash
sudo sshd -t
sudo systemctl restart ssh.socket
sudo systemctl restart ssh
sudo sshd -T | grep -E '^usepam|^kbdinteractiveauthentication|^passwordauthentication'
grep -nE 'common-auth|pam_google_authenticator|pam_exec' /etc/pam.d/sshd
```

Инициализация для `jump-test`:
```bash
#Вызов команды для настройки гугл аутентификации
sudo -u jump-test google-authenticator
#Вывод:
dop2@dop2:~$ sudo -u jump-test google-authenticator Do you want authentication tokens to be time-based (y/n) y 
Do you want authentication tokens to be time-based (y/n) y 
Do you want me to update your "/home/jump-test/.google_authenticator" file? (y/n) y 
Do you want to disallow multiple uses of the same authentication token? This restricts you to one login about every 30s, but it increases your chances to notice or even prevent man-in-the-middle attacks (y/n) y 
By default, a new token is generated every 30 seconds by the mobile app. In order to compensate for possible time-skew between the client and the server, we allow an extra token before and after the current time. This allows for a time skew of up to 30 seconds between authentication server and client. If you experience problems with poor time synchronization, you can increase the window from its default size of 3 permitted codes (one previous code, the current code, the next code) to 17 permitted codes (the 8 previous codes, the current code, and the 8 next codes). This will permit for a time skew of up to 4 minutes between client and server. 
Do you want to do so? (y/n) y

sudo ls -l /home/jump-test/.google_authenticator
#Вывод:
dop2@dop2:~$ sudo ls -l /home/jump-test/.google_authenticator
[sudo: authenticate] Password:
-r-------- 1 jump-test jump-test 162 Jul 13 22:02 /home/jump-test/.google_authenticator
```

Потом проверка с Windows:
```bash
#Заходим в новом окне терминала за нашего второго пользователя
ssh -p 2222 jump-test@192.168.31.179

#Вывод:

PS C:\Users\skame> ssh -p 2222 jump-test@192.168.31.179
(jump-test@192.168.31.179) Password:
(jump-test@192.168.31.179) Verification code:
Welcome to Ubuntu 26.04 LTS (GNU/Linux 7.0.0-27-generic x86_64)

 * Documentation:  https://docs.ubuntu.com
 * Management:     https://landscape.canonical.com
 * Support:        https://ubuntu.com/pro

 System information as of Mon Jul 13 10:02:12 PM UTC 2026

  System load:  0.1                Processes:               160
  Usage of /:   23.3% of 39.07GB   Users logged in:         0
  Memory usage: 7%                 IPv4 address for enp0s3: 192.168.31.179
  Swap usage:   0%


Expanded Security Maintenance for Applications is not enabled.

26 updates can be applied immediately.
4 of these updates are standard security updates.
To see these additional updates run: apt list --upgradable

Enable ESM Apps to receive additional future security updates.
See https://ubuntu.com/esm or run: sudo pro status


Last login: Wed Jul  8 16:26:27 2026 from 192.168.31.150
jump-test@dop2:~$
```

---
## Вспомогательная информация при факапе
 
Самый безопасный вариант — не удалить, а переименовать. Так лучше для обучения: если что-то пойдёт не так, старый файл останется.
```bash
sudo mv /home/jump-test/.google_authenticator /home/jump-test/.google_authenticator.broken.$(date +%F-%H%M%S)

#Разбор:
mv — переименовать/переместить файл
.google_authenticator — текущий 2FA-secret
.google_authenticator.broken... — backup старого файла
$(date +%F-%H%M%S) — добавить дату и время
```

Потом запускаешь заново:
```bash
#Запускаем настройку верификации
sudo -u <user_name> google-authenticator
```

# 6. 📄 Создание хелп скрипта для пользователей

Нам нужно сделать скрипт, который:

```
✅ генерирует SSH config для пользователя
✅ показывает примеры SSH port forwarding
✅ показывает примеры ProxyJump
✅ объясняет, куда вставить config на Windows/Linux/macOS
```

## 1. Что именно сделаем

Создадим команду:

```
jumphost-help
```

Она будет выводить готовую инструкцию.

Например:

```
jumphost-help dop2
```

или:

```
jumphost-help jump-test
```

Скрипт будет генерировать:

```
Host jump-host
    HostName 192.168.31.179
    User dop2
    Port 2222
```

и примеры:

```
ssh jump-host
ssh -N -L 127.0.0.1:18080:127.0.0.1:9000 jump-host
ssh private-server
```

---

## 2. Создаём скрипт

На jump host выполни:
```bash
#Создание помогатора
sudo nano /usr/local/bin/jumphost-help


#Вставь туда:

#!/usr/bin/env bash
set -euo pipefail

SSH_USER="${1:-dop2}"
JUMP_HOST="${2:-192.168.31.179}"
SSH_PORT="${3:-2222}"
PRIVATE_HOST="${4:-192.168.56.10}"
PRIVATE_USER="${5:-private-user}"

cat <<EOF
============================================================
JUMP HOST CONNECTION GUIDE
============================================================

Generated for SSH user: ${SSH_USER}
Jump host address:      ${JUMP_HOST}
SSH port:               ${SSH_PORT}

------------------------------------------------------------
1. WHERE TO PUT SSH CONFIG
------------------------------------------------------------

Linux/macOS:
    ~/.ssh/config

Windows PowerShell:
    C:\\Users\\<YourUser>\\.ssh\\config

If the file does not exist, create it.

Recommended permissions on Linux/macOS:
    chmod 700 ~/.ssh
    chmod 600 ~/.ssh/config

------------------------------------------------------------
2. BASIC SSH CONFIG
------------------------------------------------------------

Add this block to your SSH config:

Host jump-host
    HostName ${JUMP_HOST}
    User ${SSH_USER}
    Port ${SSH_PORT}
    ServerAliveInterval 60
    ServerAliveCountMax 3
    ExitOnForwardFailure yes

Connect with:

    ssh jump-host

Without SSH config, connect with:

    ssh -p ${SSH_PORT} ${SSH_USER}@${JUMP_HOST}

------------------------------------------------------------
3. LOCAL PORT FORWARDING: TEST SERVICE
------------------------------------------------------------

Example: forward local port 18080 to 127.0.0.1:9000 on the jump host.

Command:

    ssh -N -L 127.0.0.1:18080:127.0.0.1:9000 jump-host

Then open:

    http://127.0.0.1:18080

Or test with:

    curl http://127.0.0.1:18080

On Windows PowerShell use:

    curl.exe http://127.0.0.1:18080

Meaning:

    127.0.0.1:18080 on your computer
        -> SSH tunnel
        -> 127.0.0.1:9000 from the jump host side

------------------------------------------------------------
4. LOCAL PORT FORWARDING: PRIVATE NETWORK EXAMPLE
------------------------------------------------------------

Example: access a private PostgreSQL server:

    private server: ${PRIVATE_HOST}:5432
    local port:     15432

Command:

    ssh -N -L 127.0.0.1:15432:${PRIVATE_HOST}:5432 jump-host

Then configure your local app to connect to:

    Host: 127.0.0.1
    Port: 15432

Meaning:

    your computer:127.0.0.1:15432
        -> SSH tunnel
        -> ${PRIVATE_HOST}:5432 through jump host

------------------------------------------------------------
5. SSH CONFIG WITH LOCALFORWARD
------------------------------------------------------------

You can also add this block to ~/.ssh/config:

Host jump-local-test
    HostName ${JUMP_HOST}
    User ${SSH_USER}
    Port ${SSH_PORT}
    LocalForward 127.0.0.1:18080 127.0.0.1:9000
    ExitOnForwardFailure yes

Run tunnel with:

    ssh -N jump-local-test

------------------------------------------------------------
6. PROXYJUMP EXAMPLE
------------------------------------------------------------

ProxyJump is used when you need SSH access to a private server
through the jump host.

Add this to ~/.ssh/config:

Host private-server
    HostName ${PRIVATE_HOST}
    User ${PRIVATE_USER}
    ProxyJump jump-host

Then connect with:

    ssh private-server

Equivalent command without config:

    ssh -J ${SSH_USER}@${JUMP_HOST}:${SSH_PORT} ${PRIVATE_USER}@${PRIVATE_HOST}

------------------------------------------------------------
7. TROUBLESHOOTING
------------------------------------------------------------

Verbose SSH connection:

    ssh -v jump-host

Very verbose SSH connection:

    ssh -vvv jump-host

Check if local tunnel port is listening:

Linux/macOS:
    ss -ltn | grep 18080

Windows PowerShell:
    netstat -ano | findstr 18080

Common errors:

1) Permission denied
   Authentication failed. Check username, password, SSH key, or 2FA code.

2) Connection refused
   The target service is not running or target port is wrong.

3) administratively prohibited
   SSH server refused port forwarding. Check AllowTcpForwarding or PermitOpen.

4) Address already in use
   Local port is already busy. Use another local port, for example 18081.

------------------------------------------------------------
8. SECURITY NOTES
------------------------------------------------------------

- Do not share your private SSH key.
- Do not share your 2FA QR code or secret key.
- Keep tunnels bound to 127.0.0.1 unless you really need otherwise.
- Close unused tunnels with Ctrl+C.
- Use ProxyJump instead of exposing private servers directly.

============================================================
EOF
```

---
## 3. Делаем скрипт исполняемым

```bash
sudo chmod 755 /usr/local/bin/jumphost-help
```

Проверяем:
```bash
#ПРоверяем файл
ls -l /usr/local/bin/jumphost-help


#Ожидаем:
dop2@dop2:~$ ls -l /usr/local/bin/jumphost-help
-rwxr-xr-x 1 root root 4601 Jul 13 22:29 /usr/local/bin/jumphost-help
```

---
## 4. Проверяем скрипт

Запусти:
```bash
jumphost-help

#Вывод:
dop2@dop2:~$ jumphost-help jump-test
============================================================
JUMP HOST CONNECTION GUIDE
============================================================

Generated for SSH user: jump-test
Jump host address:      192.168.31.179
SSH port:               2222

------------------------------------------------------------
1. WHERE TO PUT SSH CONFIG
------------------------------------------------------------

Linux/macOS:
    ~/.ssh/config

Windows PowerShell:
    C:\Users\<YourUser>\.ssh\config

If the file does not exist, create it.

Recommended permissions on Linux/macOS:
    chmod 700 ~/.ssh
    chmod 600 ~/.ssh/config

------------------------------------------------------------
2. BASIC SSH CONFIG
------------------------------------------------------------

Add this block to your SSH config:

Host jump-host
    HostName 192.168.31.179
    User jump-test
    Port 2222
    ServerAliveInterval 60
    ServerAliveCountMax 3
    ExitOnForwardFailure yes

Connect with:

    ssh jump-host

Without SSH config, connect with:

    ssh -p 2222 jump-test@192.168.31.179

------------------------------------------------------------
3. LOCAL PORT FORWARDING: TEST SERVICE
------------------------------------------------------------

Example: forward local port 18080 to 127.0.0.1:9000 on the jump host.

Command:

    ssh -N -L 127.0.0.1:18080:127.0.0.1:9000 jump-host

Then open:

    http://127.0.0.1:18080

Or test with:

    curl http://127.0.0.1:18080

On Windows PowerShell use:

    curl.exe http://127.0.0.1:18080

Meaning:

    127.0.0.1:18080 on your computer
        -> SSH tunnel
        -> 127.0.0.1:9000 from the jump host side

------------------------------------------------------------
4. LOCAL PORT FORWARDING: PRIVATE NETWORK EXAMPLE
------------------------------------------------------------

Example: access a private PostgreSQL server:

    private server: 192.168.56.10:5432
    local port:     15432

Command:

    ssh -N -L 127.0.0.1:15432:192.168.56.10:5432 jump-host

Then configure your local app to connect to:

    Host: 127.0.0.1
    Port: 15432

Meaning:

    your computer:127.0.0.1:15432
        -> SSH tunnel
        -> 192.168.56.10:5432 through jump host

------------------------------------------------------------
5. SSH CONFIG WITH LOCALFORWARD
------------------------------------------------------------

You can also add this block to ~/.ssh/config:

Host jump-local-test
    HostName 192.168.31.179
    User jump-test
    Port 2222
    LocalForward 127.0.0.1:18080 127.0.0.1:9000
    ExitOnForwardFailure yes

Run tunnel with:

    ssh -N jump-local-test

------------------------------------------------------------
6. PROXYJUMP EXAMPLE
------------------------------------------------------------

ProxyJump is used when you need SSH access to a private server
through the jump host.

Add this to ~/.ssh/config:

Host private-server
    HostName 192.168.56.10
    User private-user
    ProxyJump jump-host

Then connect with:

    ssh private-server

Equivalent command without config:

    ssh -J jump-test@192.168.31.179:2222 private-user@192.168.56.10

------------------------------------------------------------
7. TROUBLESHOOTING
------------------------------------------------------------

Verbose SSH connection:

    ssh -v jump-host

Very verbose SSH connection:

    ssh -vvv jump-host

Check if local tunnel port is listening:

Linux/macOS:
    ss -ltn | grep 18080

Windows PowerShell:
    netstat -ano | findstr 18080

Common errors:

1) Permission denied
   Authentication failed. Check username, password, SSH key, or 2FA code.

2) Connection refused
   The target service is not running or target port is wrong.

3) administratively prohibited
   SSH server refused port forwarding. Check AllowTcpForwarding or PermitOpen.

4) Address already in use
   Local port is already busy. Use another local port, for example 18081.

------------------------------------------------------------
8. SECURITY NOTES
------------------------------------------------------------

- Do not share your private SSH key.
- Do not share your 2FA QR code or secret key.
- Keep tunnels bound to 127.0.0.1 unless you really need otherwise.
- Close unused tunnels with Ctrl+C.
- Use ProxyJump instead of exposing private servers directly.

============================================================

```

Он должен вывести инструкцию для пользователя `dop2`. Потом проверь для `jump-test`:
```bash
jumphost-help jump-test
```

Ожидаем, что в блоке SSH config будет:
```bash
Host jump-host
    HostName 192.168.31.179
    User jump-test
    Port 2222
```

---
## 5. Как передать другой private host

Например, если у тебя появится приватный сервер:
```
192.168.56.20
```

и пользователь на нём:
```
ubuntu
```

можно сгенерировать инструкцию так:
```bash
jumphost-help dop2 192.168.31.179 2222 192.168.56.20 ubuntu
```

Тогда ProxyJump-блок станет:
```
Host private-server
    HostName 192.168.56.20
    User ubuntu
    ProxyJump jump-host
```

---

## 6. Разбор скрипта

```
#!/usr/bin/env bash
```

Говорит системе запускать файл через Bash.
```
set -euo pipefail
```

Безопасный режим:
```
-e — остановиться при ошибке
-u — ошибка при использовании несуществующей переменной
-o pipefail — ошибка в pipe не будет скрыта
```

```
SSH_USER="${1:-dop2}"
```
Значит:
> Возьми первый аргумент. Если его нет, используй `dop2`.

Пример:
```
jumphost-help jump-test
```

Тогда:
```
SSH_USER=jump-test
```

---
Второй аргумент — адрес jump host. Если не передали, берём наш текущий IP.
```
JUMP_HOST="${2:-192.168.31.179}"
```

---
Третий аргумент — SSH-порт. По умолчанию `2222`.
```
SSH_PORT="${3:-2222}"
```

---
Четвёртый аргумент — пример приватного сервера. У нас это placeholder, потому что реального private server пока нет.
```
PRIVATE_HOST="${4:-192.168.56.10}"
```

---
Это heredoc.
```
cat <<EOF
...
EOF
```
Он говорит:
> Выведи большой текст до строки `EOF`.


Внутри текста переменные подставляются автоматически:
```
${SSH_USER}
${JUMP_HOST}
${SSH_PORT}
```

---
## 7. Почему этот скрипт безопасный

Он:
```
не меняет sshd_config
не меняет PAM
не меняет iptables
не создаёт пользователей
не трогает ключи
```

Он только печатает инструкцию.

То есть его можно спокойно давать пользователям.

---
## 8. Дополнительно: сохранить инструкцию в файл

Если хочешь сгенерировать файл для пользователя:
```bash
jumphost-help jump-test > /tmp/jump-test-ssh-guide.txt
```

Проверить:
```bash
cat /tmp/jump-test-ssh-guide.txt
```

Можно отдать пользователю содержимое этого файла.
