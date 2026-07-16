# 0. Что мы строим

Представим, что Nginx — это **администратор на ресепшене**. Клиент приходит и говорит:
```
Хочу попасть в app.example.local
```

Nginx отвечает:
```
Окей, я сам решу, к какому серверу приложения тебя отправить:
3001, 3002 или 3003.
```

Схема будет такая:
```
Клиент / браузер / curl
        ↓
Nginx :80 / :443
        ↓
upstream app_backend
        ↓
localhost:3001
localhost:3002
localhost:3003
```

То есть клиент не знает про `3001`, `3002`, `3003`, а Nginx уже сам балансирует нагрузку. Он знает только:
```
https://app.example.local
```

---
# 1 Важный момент про iptables

Мы на прошлом задании [[Jump host]] настроили `iptables` с политикой:
```
INPUT DROP
OUTPUT DROP
FORWARD DROP
```

Это значит: если мы хотим открывать Nginx с Windows, нам надо будет **разрешить входящие 80 и 443** хотя бы с твоего IP:
```
192.168.31.150
```
Но вначале подготовим Nginx и backend-ы. Потом аккуратно добавим firewall-правила.

---
# 2. План практики

Будем делать по блокам:
```
1. Подготовка окружения
2. Установка Nginx
3. Создание трёх тестовых backend-сервисов
4. Создание self-signed SSL-сертификата
5. Настройка upstream
6. Настройка HTTP → HTTPS редиректа
7. Настройка HTTPS reverse proxy
8. Настройка таймаутов и client_max_body_size
9. Настройка кеширования статики
10. Настройка логирования
11. Настройка logrotate
12. Настройка rate limiting
13. Скрытие версии Nginx
14. Проверка балансировки
15. Проверка отказоустойчивости backend
16. Итоговый отчёт
```

---
# 3. Сначала проверяем текущее состояние

Выполняем на сервере:
```bash
#Покажет имя сервера.
hostname

#Покажет IP-адреса. Нас интересует: 192.168.31.179
ip -br a

#Показывает, какие порты уже слушаются. (Если порты по заданию заняты возьмем другие или уберем того кто их занял)
ss -tulpn | grep -E ':80|:443|:3001|:3002|:3003|nginx'

#Смотрим наши правила для iptables
sudo iptables -S | head -n 30
```

---
# 4. Устанавливаем Nginx

```bash
#Обновляем пакеты 
sudo apt update

#Устанавливаем nginx
sudo apt install -y nginx

#Проверяем разными способами что nginx есть на сервере
#============================================================================

dop2@dop2:~$ which nginx
/usr/sbin/nginx

#============================================================================

dop2@dop2:~$ nginx -version
nginx version: nginx/1.28.3 (Ubuntu)

#============================================================================

dop2@dop2:~$ sudo systemctl status nginx --no-pager
● nginx.service - A high performance web server and a reverse proxy server
     Loaded: loaded (/usr/lib/systemd/system/nginx.service; enabled; preset: enabled)
     Active: active (running) since Tue 2026-07-14 09:48:02 UTC; 3h 11min ago
 Invocation: 407cb6de6f7a4a009c259c9a22dedaf6
       Docs: man:nginx(8)
   Main PID: 1451 (nginx)
      Tasks: 5 (limit: 3971)
     Memory: 5.9M (peak: 6.8M)
        CPU: 19ms
     CGroup: /system.slice/nginx.service
             ├─1451 "nginx: master process /usr/sbin/nginx -g daemon on; master_process on;"
             ├─1452 "nginx: worker process"
             ├─1453 "nginx: worker process"
             ├─1454 "nginx: worker process"
             └─1455 "nginx: worker process"

Jul 14 09:48:01 dop2 systemd[1]: Starting nginx.service - A high performance web server and a reverse proxy server...
Jul 14 09:48:02 dop2 systemd[1]: Started nginx.service - A high performance web server and a reverse proxy server.
#============================================================================

```

----
# 5. Создадим тестовые backend-ы

Чтобы реально увидеть балансировку, нам нужны три сервиса. Сделаем простые backend-и на Python. Каждый будет отвечать своим именем:
```
backend-1
backend-2
backend-3
```

Создаём директории там где это удобнее, в нашем случае будет папка для домашней работы и так же создаем легкие html страницы:
```bash
#Создание папок
mkdir LiTasks/task7 LiTasks/task7/backend-{1..3}

#Вывод
dop2@dop2:~$ mkdir LiTasks/task7 LiTasks/task7/backend-{1..3}
dop2@dop2:~$ ls -l LiTasks/task7
total 12
drwxrwxr-x 2 dop2 dop2 4096 Jul 14 13:24 backend-1
drwxrwxr-x 2 dop2 dop2 4096 Jul 14 13:24 backend-2
drwxrwxr-x 2 dop2 dop2 4096 Jul 14 13:24 backend-3

#Создаем последовательно страницы в каждой папке
echo "Hello from backend-1 on port 3001" > ~/LiTasks/task7/backend-1/index.html

echo "Hello from backend-2 on port 3002" > ~/LiTasks/task7/backend-2/index.html

echo "Hello from backend-3 on port 3003" > ~/LiTasks/task7/backend-3/index.html

#Вывод
dop2@dop2:~$ ls -l ./LiTasks/task7/backend-1 ./LiTasks/task7/backend-2 ./LiTasks/task7/backend-3
./LiTasks/task7/backend-1:
total 4
-rw-rw-r-- 1 dop2 dop2 34 Jul 14 13:32 index.html

./LiTasks/task7/backend-2:
total 4
-rw-rw-r-- 1 dop2 dop2 34 Jul 14 13:32 index.html

./LiTasks/task7/backend-3:
total 4
-rw-rw-r-- 1 dop2 dop2 34 Jul 14 13:33 index.html

```

---
# 6. Запускаем и проверяем backend-ы вручную для первого теста 

Открой **три отдельных SSH-окна** для запуска бэкэндов и так же четвертое окно для проверки:
```bash
#Певрое окно на сервере
python3 -m http.server 3001 --bind 127.0.0.1 --directory ~/LiTasks/task7/backend-1

#Второе окно на сервере
python3 -m http.server 3002 --bind 127.0.0.1 --directory ~/LiTasks/task7/backend-2

#Третье окно на сервере
python3 -m http.server 3003 --bind 127.0.0.1 --directory ~/LiTasks/task7/backend-3

#Запуск в трех окнах
#=======================================================================

dop2@dop2:~$ python3 -m http.server 3001 --bind 127.0.0.1 --directory ~/LiTasks/task7/backend-1
Serving HTTP on 127.0.0.1 port 3001 (http://127.0.0.1:3001/) ...

#=======================================================================

dop2@dop2:~$ python3 -m http.server 3002 --bind 127.0.0.1 --directory ~/LiTasks/task7/backend-2
Serving HTTP on 127.0.0.1 port 3002 (http://127.0.0.1:3002/) ...

#=======================================================================

dop2@dop2:~$ python3 -m http.server 3003 --bind 127.0.0.1 --directory ~/LiTasks/task7/backend-3
Serving HTTP on 127.0.0.1 port 3003 (http://127.0.0.1:3003/) ...

#=======================================================================

#Вывод из 4ого окна
dop2@dop2:~$ curl http://127.0.0.1:3001
Hello from backend-1 on port 3001
dop2@dop2:~$ curl http://127.0.0.1:3002
Hello from backend-2 on port 3002
dop2@dop2:~$ curl http://127.0.0.1:3003
Hello from backend-3 on port 3003
dop2@dop2:~$


#Вывод моментальных логов из окон с бэкэндами
#=======================================================================

dop2@dop2:~$ python3 -m http.server 3001 --bind 127.0.0.1 --directory ~/LiTasks/task7/backend-1
Serving HTTP on 127.0.0.1 port 3001 (http://127.0.0.1:3001/) ...
127.0.0.1 - - [14/Jul/2026 14:52:46] "GET / HTTP/1.1" 200 -

#=======================================================================

dop2@dop2:~$ python3 -m http.server 3002 --bind 127.0.0.1 --directory ~/LiTasks/task7/backend-2
Serving HTTP on 127.0.0.1 port 3002 (http://127.0.0.1:3002/) ...
127.0.0.1 - - [14/Jul/2026 14:52:51] "GET / HTTP/1.1" 200 -

#=======================================================================

dop2@dop2:~$ python3 -m http.server 3003 --bind 127.0.0.1 --directory ~/LiTasks/task7/backend-3
Serving HTTP on 127.0.0.1 port 3003 (http://127.0.0.1:3003/) ...
127.0.0.1 - - [14/Jul/2026 14:52:55] "GET / HTTP/1.1" 200 -

#=======================================================================
```

> [!NOTE]
> Почему `127.0.0.1`? Мы специально биндим backend-ы только на localhost 127.0.0.1.
> 
> Это значит доступ к ним должен идти только через Nginx и снаружи напрямую к backend-ам не подключиться. Это production-подход: backend-и не торчат наружу.
> 

----
## 6.1 Альтернативы для backend-ов

### Вариант A: Python http.server

Плюсы:
1. быстро
2. ничего почти не надо писать
3. идеально для учебной проверки

Минусы:
1. не production backend

---
### Вариант B: Docker

Можно поднять три контейнера:
```bash
docker run -d --name backend-1 -p 127.0.0.1:3001:80 nginx
docker run -d --name backend-2 -p 127.0.0.1:3002:80 nginx
docker run -d --name backend-3 -p 127.0.0.1:3003:80 nginx
```

Плюсы:
1. Похоже на реальную инфраструктуру

Минусы:
1. Нужно аккуратно учитывать Docker + iptables

У нас уже есть firewall-настройки, поэтому сейчас Python безопаснее.

---
### Вариант C: маленькое Flask-приложение

Можно сделать 3 Flask backend-а, каждый будет возвращать JSON.

Плюсы:
1. похоже на реальное приложение/API

Минусы:
1. нужно ставить зависимости

Для этой практики берём Python `http.server`, потому что цель — Nginx, а не разработка приложения.

----
### Вариант D: Настроить через systemd

Это самый правильный вариант, если хотим “как сервис”. Аналогия: `systemd` — это менеджер смен. Он знает, кто должен работать, может запускать, останавливать, показывать статус и логи.

Плюсы:
1. можно делать start/stop/restart/status
2. есть логи через journalctl
3. можно включить автозапуск
4. процесс не зависит от SSH-сессии


Минусы:
1. чуть больше настройки

Для production или красивой практики — лучший вариант.

----
# 7. Создаём директорию для сертификата

```bash
#Создаем папку для нашего самоподписанного сертификата
sudo mkdir -p /etc/nginx/ssl

#Разбор:
sudo — нужны права root
mkdir — создать директорию
-p — не ругаться, если директория уже существует
/etc/nginx/ssl — место, где будем хранить ключ и сертификат
```

----
# 8. Создаём self-signed сертификат

Далее необходимо выполнить:
```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/app.example.local.key \
  -out /etc/nginx/ssl/app.example.local.crt \
  -subj "/C=FI/ST=Pirkanmaa/L=Hameenkyro/O=DevOpsLab/OU=Practice/CN=app.example.local" \
  -addext "subjectAltName=DNS:app.example.local,IP:192.168.31.179"


#Разбор команд
#==========================================================================
#Создаёт сертификат или certificate signing request.
openssl req

#Создать сразу самоподписанный сертификат, а не запрос на сертификат
-x509

#Не шифровать private key паролем. Почему так? Если ключ будет с паролем, Nginx при каждом старте будет ждать ввод пароля. Для сервера это неудобно.
-nodes

#Сертификат будет действовать 365 дней.
-days 365

#Создать новый RSA-ключ длиной 2048 бит.
-newkey rsa:2048

#Куда сохранить private key.
-keyout

#Куда сохранить сертификат.
-out

#Данные сертификата без интерактивных вопросов.
-subj

#Добавляем SAN. Это важно: современные клиенты смотрят не только на `CN`, но и на `subjectAltName`.
-addext "subjectAltName=..."

#Вывод
dop2@dop2:/$ sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048   -keyout /etc/nginx/ssl/app.example.local.key   -out /etc/nginx/ssl/app.example.local.crt   -subj "/C=FI/ST=Pirkanmaa/L=Hameenkyro/O=DevOpsLab/OU=Practice/CN=app.example.local"   -addext "subjectAltName=DNS:app.example.local,IP:192.168.31.179"
....+.........+.....+.+........+...+...+................+......+...+.....+......+.+...+..+.........+....+......+.........+..+....+....................+...+..........+...+.....+...+....+++++++++++++++++++++++++++++++++++++++*...+................+.........+...+..+...+.......+...+...+............+..+++++++++++++++++++++++++++++++++++++++*.......+.........+.+.....+..........+.....+.+......+.....+..........+............+..+...+...+.......+........+...+.+...+.....+...+..........+........+.+......+............+........+...+......+...............+...+..........+..+....+......+......+...+..+.........+...............+.+..+.......+...........+.......+..+...............+.............+.....+.+..+...+.......+...+...........+....+...........+.+..+.+..+...+.......+..............+......+...++++++
......+...+++++++++++++++++++++++++++++++++++++++*..+..............+....+.....+..........+.....+......+.+..+...+.........+......+.......+..+....+.........+......+.....+.+...+...+........+++++++++++++++++++++++++++++++++++++++*................+...+.........+.......+.....+......+...+.+......+...+..+...+................+........+...+...+......+.++++++
-----
```

---
## 8.1 Альтернативы self-signed сертификату

### Вариант 1: self-signed через openssl

Это то, что мы делаем.

Плюсы:
1. быстро
2. не нужен реальный домен
3. идеально для лаборатории

Минусы:
1. браузер будет ругаться
2. сертификату никто не доверяет
---
### Вариант 2: mkcert

`mkcert` создаёт локальный доверенный CA и сертификаты для локальной разработки:

Плюсы:
1. удобно для локальной разработки
2. браузер может доверять сертификату

Минусы:
1. надо ставить mkcert
2. это не production
---
### Вариант 3: Let’s Encrypt

Production-вариант:
Плюсы:
1. бесплатный настоящий сертификат
2. браузеры доверяют
3. автоматическое продление
Минусы:
4. нужен реальный домен
5. нужна доступность снаружи
6. для app.example.local не подойдёт

---
# 9. Проверяем сертификат

```bash
#Проверяем содержимое папки ssl
sudo ls -l /etc/nginx/ssl/

#Ожидаемый вывод должен быть примерно таким:
dop2@dop2:/$ sudo ls -l /etc/nginx/ssl/
total 8
-rw-r--r-- 1 root root 1436 Jul 15 13:32 app.example.local.crt
-rw------- 1 root root 1704 Jul 15 13:32 app.example.local.key

#Права на key лучше сделать строгими:
sudo chmod 600 /etc/nginx/ssl/app.example.local.key
sudo chmod 644 /etc/nginx/ssl/app.example.local.crt

#Проверяем
sudo openssl x509 -in /etc/nginx/ssl/app.example.local.crt -noout -subject -issuer -dates

#Вывод:
dop2@dop2:/$ sudo openssl x509 -in /etc/nginx/ssl/app.example.local.crt -noout -subject -issuer -dates

subject=C=FI, ST=Pirkanmaa, L=Hameenkyro, O=DevOpsLab, OU=Practice, CN=app.example.local
issuer=C=FI, ST=Pirkanmaa, L=Hameenkyro, O=DevOpsLab, OU=Practice, CN=app.example.local
notBefore=Jul 15 13:32:52 2026 GMT
notAfter=Jul 15 13:32:52 2027 GMT
```

----
# 10. Следующий шаг: глобальные настройки Nginx

Нам нужны настройки, которые должны жить внутри `http`-контекста Nginx:
```conf
log_format
proxy_cache_path
limit_req_zone
server_tokens off
```

Аналогия:
```txt
http-контекст — это правила для всего здания Nginx.
server block — это правила для конкретного офиса/домена.
location — это правила для конкретной комнаты/пути.
```

Создаём отдельный файл:
```bash
#Создаем наш самодельный конфиг и кладем в специальную папку от nginx
sudo nano /etc/nginx/conf.d/app-lb-global.conf


#Далее в наш конфиг вставим данный код:
server_tokens off;

log_format upstream_timing '$remote_addr - $remote_user [$time_local] "$request" '
                           '$status $body_bytes_sent "$http_referer" '
                           '"$http_user_agent" '
                           'rt=$request_time ' 
                           'uct=$upstream_connect_time '
                           'uht=$upstream_header_time '
                           'urt=$upstream_response_time '
                           'upstream=$upstream_addr';

proxy_cache_path /var/cache/nginx/app_static
                 levels=1:2
                 keys_zone=app_static_cache:10m
                 max_size=100m
                 inactive=30d
                 use_temp_path=off;

limit_req_zone $binary_remote_addr zone=app_rate_limit:10m rate=10r/s;

#Разбор нашего конфига
#============================================================================
#Скрывает версию Nginx в ошибках и заголовках. То есть вместо "nginx/1.28.3" будет просто nginx
server_tokens off;

#Создаёт свой формат access log. 
log_format upstream_timing '$remote_addr - $remote_user [$time_local] "$request" '
                           '$status $body_bytes_sent "$http_referer" '
                           '"$http_user_agent" '
                           'rt=$request_time ' #сколько отвечал запрос
                           'uct=$upstream_connect_time '
                           'uht=$upstream_header_time '
                           'urt=$upstream_response_time '#какой backend обработал запрос
                           'upstream=$upstream_addr';#сколько отвечал backend


#Создаёт зону кеша. Аналогия: кеш — это склад готовых ответов.Если клиент просит одну и ту же картинку много раз, Nginx может не ходить каждый раз к backend, а отдать файл из кеша.
proxy_cache_path

#Создаёт зону rate limiting. С одного IP можно не больше 10 запросов в секунду
limit_req_zone
```

---
# 11. Создаём директорию кеша

```bash
#Создаем папку для хранения файлов в кеше
sudo mkdir -p /var/cache/nginx/app_static

#Даем права на запись в этой папке
sudo chown -R www-data:www-data /var/cache/nginx/app_static
```

> [!NOTE]
> Почему `www-data`?
> На Ubuntu Nginx worker-процессы обычно работают от пользователя `www-data`. Значит этот пользователь должен иметь доступ к директории кеша.

---
# 12. Создаём конфиг сайта

```bash
#Создаем конфиг для сайта в sites-available
sudo nano /etc/nginx/sites-available/app.example.local


#Надо вставить данный код в конф файл
upstream app_backend {
    server 127.0.0.1:3001 max_fails=2 fail_timeout=30s;
    server 127.0.0.1:3002 max_fails=2 fail_timeout=30s;
    server 127.0.0.1:3003 max_fails=2 fail_timeout=30s;
}

server {
    listen 80;
    listen [::]:80;

    server_name app.example.local;

    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;

    server_name app.example.local;

    ssl_certificate     /etc/nginx/ssl/app.example.local.crt;
    ssl_certificate_key /etc/nginx/ssl/app.example.local.key;

    access_log /var/log/nginx/app_access.log upstream_timing;
    error_log  /var/log/nginx/app_error.log warn;

    client_max_body_size 100M;

    location ~* \.(jpg|jpeg|png|gif|ico)$ {
        proxy_cache app_static_cache;
        proxy_cache_valid 200 30d;

        expires 30d;
        add_header Cache-Control "public, max-age=2592000, immutable" always;
        add_header X-Cache-Status $upstream_cache_status always;

        proxy_pass http://app_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location ~* \.(css|js)$ {
        proxy_cache app_static_cache;
        proxy_cache_valid 200 30d;

        expires 30d;
        add_header Cache-Control "public, max-age=2592000, immutable" always;
        add_header X-Cache-Status $upstream_cache_status always;

        proxy_pass http://app_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location / {
        limit_req zone=app_rate_limit burst=20 nodelay;

        proxy_pass http://app_backend;

        proxy_http_version 1.1;

        proxy_connect_timeout 5s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;

        proxy_next_upstream error timeout http_500 http_502 http_503 http_504;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

#Проверяем что у нас сохздан файл
ls -l /etc/nginx/sites-available/app.example.local

#Вывод по команде
dop2@dop2:/$ ls -l /etc/nginx/sites-available/app.example.local
-rw-r--r-- 1 root root 2280 Jul 15 15:26 /etc/nginx/sites-available/app.example.local
```

---
# 13. Разбор команды. Что здесь важно

```bash
# Upstream app_backend это группа backend-ов.
upstream app_backend {
    server 127.0.0.1:3001 max_fails=2 fail_timeout=30s;
    server 127.0.0.1:3002 max_fails=2 fail_timeout=30s;
    server 127.0.0.1:3003 max_fails=2 fail_timeout=30s;
}

#Если backend дважды не ответил — временно считать его плохим.
max_fails=2

#На 30 секунд исключить backend из нормальной ротации.
fail_timeout=30s

# HTTP → HTTPS redirect. Если клиент пришёл на http://app.example.local -> отправить его на https://app.example.local
return 301 https://$host$request_uri;

# proxy_pass. Это главная строка reverse proxy. запрос пришёл в Nginx и Nginx передал его в upstream app_backend
proxy_pass http://app_backend;

# timeout-ы
#сколько ждать установления соединения с backend
proxy_connect_timeout 5s;
#сколько ждать отправки запроса backend-у
proxy_send_timeout 60s;
#сколько ждать ответа от backend
proxy_read_timeout 60s;
```
Важно: в open-source Nginx это **passive health check**. То есть Nginx понимает, что backend плохой, только когда реальный запрос на него неудачно сходил.

---
# 14. Включаем сайт и проверяем конфигурацию

```bash
#Создаем симлинк в папку sites-enabled(Если ссылка уже есть, будет ошибка. Это не страшно).
sudo ln -s /etc/nginx/sites-available/app.example.local /etc/nginx/sites-enabled/app.example.local

#Проверяем командой:
ls -l /etc/nginx/sites-enabled/

#Вывод
dop2@dop2:/$ ls -l /etc/nginx/sites-enabled/
total 0
lrwxrwxrwx 1 root root 44 Jul 15 15:23 app.example.local -> /etc/nginx/sites-available/app.example.local
lrwxrwxrwx 1 root root 34 Jul  4 12:49 default -> /etc/nginx/sites-available/default

#Проверяем конфигурацию на ошибки
sudo nginx -t

#Предпологаемыйц вывод если нет проблем
dop2@dop2:/$ sudo nginx -t
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful

#Далее даем команду nginx перечитать конфиг без перезагрузки(без падения сервиса)
sudo systemctl reload nginx

```

---
# 15. Добавляем hosts-запись на сервере

```bash
#Добавляем на сервере в ручной файл hosts запись
echo "127.0.0.1 app.example.local" | sudo tee -a /etc/hosts

#Проверяем 
getent hosts app.example.local

#Успешные выводы команд
dop2@dop2:/$ echo "127.0.0.1 app.example.local" | sudo tee -a /etc/hosts
127.0.0.1 app.example.local
dop2@dop2:/$ getent hosts app.example.local
127.0.0.1       app.example.local
```

---
# 16. Проверяем HTTP redirect

```bash
#Проверяем с помощью веб-сервер с помощью курла
curl -I http://app.example.local

#Успешный вывод команды:
dop2@dop2:/$ curl -I http://app.example.local
HTTP/1.1 301 Moved Permanently
Server: nginx/1.28.3 (Ubuntu)
Date: Wed, 15 Jul 2026 15:50:57 GMT
Content-Type: text/html
Content-Length: 178
Connection: keep-alive
Location: https://app.example.local/

#Если увидим такой ответ может быть проблема с default, его можно удалить из папки sites-enebled 
dop2@dop2:/$ curl -I http://app.example.local
HTTP/1.1 200 OK
Server: nginx/1.28.3 (Ubuntu)
Date: Wed, 15 Jul 2026 15:40:05 GMT
Content-Type: text/html
Content-Length: 615
Last-Modified: Sat, 04 Jul 2026 12:49:03 GMT
Connection: keep-alive
ETag: "6a49013f-267"
Accept-Ranges: bytes

#и так же если видим версию nginx у нас проблемы с оригинальным конфигом nginx идем в папку /etc/nginx и правим nginx.conf
sudo nano /etc/nginx/nginx.conf
#Правим server_tokens build -> server_tokens off 
#Проверяем конфиг на ошибки 
sudo nginx -t 
#Затем релоудим наш сервис
sudo systemctl reload nginx

#Повторная проверка:
dop2@dop2:~$ curl -I http://app.example.local
HTTP/1.1 301 Moved Permanently
Server: nginx
Date: Wed, 15 Jul 2026 16:13:49 GMT
Content-Type: text/html
Content-Length: 162
Connection: keep-alive
Location: https://app.example.local/
```

---
# 17. Проверяем HTTPS

```bash
#Так как сертификат самоподписанный, используем `-k`

dop2@dop2:/$ curl -k https://app.example.local
Hello from backend-1 on port 3001

dop2@dop2:/$ curl -k https://app.example.local
Hello from backend-1 on port 3001

dop2@dop2:/$ curl -k https://app.example.local
Hello from backend-1 on port 3001

dop2@dop2:/$ curl -k https://app.example.local
Hello from backend-3 on port 3003

dop2@dop2:/$ curl -k https://app.example.local
Hello from backend-2 on port 3002

dop2@dop2:/$ curl -k https://app.example.local
Hello from backend-3 on port 3003

dop2@dop2:/$ curl -k https://app.example.local
Hello from backend-1 on port 3001

dop2@dop2:/$ curl -k https://app.example.local
Hello from backend-2 on port 3002

dop2@dop2:/$ curl -k https://app.example.local
Hello from backend-3 on port 3003

dop2@dop2:/$ curl -k https://app.example.local
Hello from backend-1 on port 3001

dop2@dop2:/$ curl -k https://app.example.local
Hello from backend-2 on port 3002

dop2@dop2:/$ curl -k https://app.example.local
Hello from backend-3 on port 3003
```

---
# 18. Создаём и проверяем тестовый CSS-файл на backend-ах

Создадим легкие css файлы 
```bash
echo 'body { background: white; } /* backend-1 css */' > ~/LiTasks/task7/backend-1/style.css

echo 'body { background: white; } /* backend-2 css */' > ~/LiTasks/task7/backend-2/style.css

echo 'body { background: white; } /* backend-3 css */' > ~/LiTasks/task7/backend-3/style.css

#Проверяем напрямую
dop2@dop2:~$ curl http://127.0.0.1:3001/style.css
body { background: white; } /* backend-1 css */

dop2@dop2:~$ curl http://127.0.0.1:3002/style.css
body { background: white; } /* backend-2 css */

dop2@dop2:~$ curl http://127.0.0.1:3003/style.css
body { background: white; } /* backend-3 css */
```

Почему я специально сделал разные комментарии? Чтобы увидеть, с какого backend-а Nginx впервые забрал файл. В production так делать не надо: статика с одинаковым URL должна быть одинаковой на всех backend-ах.

---
# 19. Очищаем кеш перед тестом

Чтобы тест был честный:
```bash
#Удаляем кэш перед проверкой
sudo rm -rf /var/cache/nginx/app_static/*

#Просим перечитать конфиги
sudo systemctl reload nginx



#Проверим, что кеш пустой:
sudo find /var/cache/nginx/app_static -type f | wc -l

#Вывод:
dop2@dop2:~$ sudo find /var/cache/nginx/app_static -type f | wc -l
0 #Значит все хорошо
```

---
# 20. Первый запрос к CSS через Nginx

```bash
#Первый запрос
#===========================================================================
curl -k -I https://app.example.local/style.css

#Смотри на заголовки:
Cache-Control
Expires
X-Cache-Status

#Ожидаем примерно:
HTTP/1.1 200 OK
Server: nginx
Date: Wed, 15 Jul 2026 16:42:32 GMT
Content-Type: text/css
Content-Length: 48
Connection: keep-alive
Last-Modified: Wed, 15 Jul 2026 16:36:11 GMT
Expires: Fri, 14 Aug 2026 16:42:32 GMT
Cache-Control: max-age=2592000
Cache-Control: public, max-age=2592000, immutable
X-Cache-Status: MISS #Нормально. Это первый запрос, кеш ещё пустой.
#===========================================================================

#Второй запрос
#===========================================================================
curl -k -I https://app.example.local/style.css

#Ожидаем примерно:
HTTP/1.1 200 OK
Server: nginx
Date: Wed, 15 Jul 2026 16:44:03 GMT
Content-Type: text/css
Content-Length: 48
Connection: keep-alive
Last-Modified: Wed, 15 Jul 2026 16:36:11 GMT
Expires: Fri, 14 Aug 2026 16:44:03 GMT
Cache-Control: max-age=2592000
Cache-Control: public, max-age=2592000, immutable
X-Cache-Status: HIT #Это значит Nginx отдал файл из кеша.
```

---
# **21. Проверим тело файла**

```bash
#Делаем запрос
curl -k https://app.example.local/style.css


#Ты увидишь CSS и комментарий одного из backend-ов. Если после этого повторять запрос, скорее всего будет отдаваться тот же вариант, потому что файл уже закеширован.
#Запрос + Вывод
dop2@dop2:~$ curl -k https://app.example.local/style.css
body { background: white; } /* backend-1 css */

dop2@dop2:~$ curl -k https://app.example.local/style.css
body { background: white; } /* backend-1 css */

dop2@dop2:~$ curl -k https://app.example.local/style.css
body { background: white; } /* backend-1 css */
```

---
# 22. Проверяем, что кеш-файлы появились

```bash
#Проверяем папку с кэшом
sudo find /var/cache/nginx/app_static -type f | wc -l
#Ожидаем уже не `0`, а например:
1

#вывод:
dop2@dop2:~$ sudo find /var/cache/nginx/app_static -type f | wc -l
1
```

## 22.1 Альтернативные способы проверить кеш

### Вариант 1: смотреть только заголовки

Это самый удобный и простой способ.
```bash
curl -k -I https://app.example.local/style.css
```

---
### Вариант 2: смотреть заголовки и тело

```bash
curl -k -i https://app.example.local/style.css

#Разница:
-I — только headers
-i — headers + body
```

---
### Вариант 3: смотреть access log

```bash
sudo tail -f /var/log/nginx/app_access.log

#В другом окне делай:
curl -k https://app.example.local/style.css
#В логах мы должны видеть время ответа и upstream.
```

---
# 23. Проверка rate limiting

Теория коротко:
Rate limiting — это ограничение скорости запросов.

Аналогия: охранник на входе. Если человек спокойно заходит 1-2 запроса в секунду его пускают.

Если с одного IP начинается шквал: 50 запросов почти одновременно, то Nginx начинает часть запросов отклонять.

У нас настроено:
```bash
#В нашем конфиге настроено вот так:
limit_req_zone $binary_remote_addr zone=app_rate_limit:10m rate=10r/s;
limit_req zone=app_rate_limit burst=20 nodelay;

#Смысл:
rate=10r/s # базово разрешено 10 запросов в секунду с одного IP
burst=20 # можно кратковременно превысить лимит до 20 запросов
nodelay # лишние запросы не задерживать, а быстро обрабатывать/отклонять


# Нагрузочный мини-тест через `xargs`
Выполни:
#Команда для проверки rate limit
seq 1 80 | xargs -I{} -P40 sh -c 'curl -k -s -o /dev/null -w "%{http_code}\n" https://app.example.local/' | sort | uniq -c


#Разбор:
seq 1 80     — создать 80 чисел, то есть 80 запросов
xargs        — запускать команды
-P40         — до 40 параллельных процессов
curl         — делает запрос
%{http_code} — вывести только HTTP-код
sort | uniq -c — посчитать, сколько каких кодов было

#Примерный результат может быть примерно такой:
	30 200
	50 503

#Наш вывод:
dop2@dop2:~$ seq 1 80 | xargs -I{} -P40 sh -c 'curl -k -s -o /dev/null -w "%{http_code}\n" https://app.example.local/' | sort | uniq -c
     22 200
     58 503
```

Или другое соотношение. Главное, чтобы появились не только `200`, но и `503`. `503` здесь не значит, что Nginx сломался. Это значит:

- rate limiting сработал и часть запросов была отклонена
---
# 24. Проверяем лог rate limit

```bash
#Проверяем последние 50 строчек файла app_error.log
sudo tail -n 50 /var/log/nginx/app_error.log

#Вывод
dop2@dop2:~$ sudo tail -n 50 /var/log/nginx/app_error.log
2026/07/15 17:01:55 [error] 6460#6460: *101 limiting requests, excess: 20.180 by zone "app_rate_limit", client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", host: "app.example.local"
2026/07/15 17:01:55 [error] 6461#6461: *113 limiting requests, excess: 20.170 by zone "app_rate_limit", client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", host: "app.example.local"
2026/07/15 17:01:55 [error] 6461#6461: *114 limiting requests, excess: 20.150 by zone "app_rate_limit", client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", host: "app.example.local"
2026/07/15 17:01:55 [error] 6461#6461: *115 limiting requests, excess: 20.130 by zone "app_rate_limit", client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", host: "app.example.local"
2026/07/15 17:01:55 [error] 6460#6460: *108 limiting requests, excess: 20.110 by zone "app_rate_limit", client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", host: "app.example.local"
2026/07/15 17:01:55 [error] 6461#6461: *116 limiting requests, excess: 20.090 by zone "app_rate_limit", client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", host: "app.example.local"
2026/07/15 17:01:55 [error] 6462#6462: *112 limiting requests, excess: 20.050 by zone "app_rate_limit", client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", host: "app.example.local"
2026/07/15 17:01:55 [error] 6461#6461: *118 limiting requests, excess: 20.030 by zone "app_rate_limit", client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", host: "app.example.local"
2026/07/15 17:01:55 [error] 6461#6461: *123 limiting requests, excess: 20.920 by zone "app_rate_limit", client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", host: "app.example.local"
2026/07/15 17:01:55 [error] 6462#6462: *124 limiting requests, excess: 20.920 by zone "app_rate_limit", client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", host: "app.example.local"
2026/07/15 17:01:55 [error] 6462#6462: *128 limiting requests, excess: 20.890 by zone "app_rate_limit", client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", host: "app.example.local"
2026/07/15 17:01:55 [error] 6461#6461: *122 limiting requests, excess: 20.760 by zone "app_rate_limit", client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", host: "app.example.local"
2026/07/15 17:01:55 [error] 6462#6462: *136 limiting requests, excess: 20.750 by zone "app_rate_limit", client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", host: "app.example.local"
2026/07/15 17:01:55 [error] 6459#6459: *127 limiting requests, excess: 20.730 by zone "app_rate_limit", client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", host: "app.example.local"
2026/07/15 17:01:55 [error] 6462#6462: *129 limiting requests, excess: 20.660 by zone "app_rate_limit", client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", host: "app.example.local"
2026/07/15 17:01:55 [error] 6459#6459: *126 limiting requests, excess: 20.660 by zone "app_rate_limit", client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", host: "app.example.local"
2026/07/15 17:01:55 [error] 6462#6462: *138 limiting requests, excess: 20.660 by zone "app_rate_limit", client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", host: "app.example.local"
2026/07/15 17:01:55 [error] 6459#6459: *142 limiting requests, excess: 20.630 by zone "app_rate_limit", client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", host: "app.example.local"
2026/07/15 17:01:55 [error] 6459#6459: *144 limiting requests, excess: 20.620 by zone "app_rate_limit", client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", host: "app.example.local"
2026/07/15 17:01:55 [error] 6460#6460: *141 limiting requests, excess: 20.610 by zone "app_rate_limit", client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", host: "app.example.local"
2026/07/15 17:01:55 [error] 6462#6462: *132 limiting requests, excess: 20.600 by zone "app_rate_limit", client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", host: "app.example.local"
2026/07/15 17:01:55 [error] 6462#6462: *130 limiting requests, excess: 20.590 by zone "app_rate_limit", client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", host: "app.example.local"
2026/07/15 17:01:55 [error] 6462#6462: *131 limiting requests, excess: 20.580 by zone "app_rate_limit", client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", host: "app.example.local"
2026/07/15 17:01:55 [error] 6462#6462: *121 limiting requests, excess: 20.580 by zone "app_rate_limit", client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", host: "app.example.local"
2026/07/15 17:01:55 [error] 6459#6459: *135 limiting requests, excess: 20.570 by zone "app_rate_limit", client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", host: "app.example.local"
2026/07/15 17:01:55 [error] 6462#6462: *133 limiting requests, excess: 20.560 by zone "app_rate_limit", client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", host: "app.example.local"
2026/07/15 17:01:55 [error] 6461#6461: *117 limiting requests, excess: 20.550 by zone "app_rate_limit", client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", host: "app.example.local"
2026/07/15 17:01:55 [error] 6459#6459: *149 limiting requests, excess: 20.540 by zone "app_rate_limit", client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", host: "app.example.local"
2026/07/15 17:01:55 [error] 6459#6459: *150 limiting requests, excess: 20.530 by zone "app_rate_limit", client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", host: "app.example.local"
2026/07/15 17:01:55 [error] 6462#6462: *134 limiting requests, excess: 20.520 by zone "app_rate_limit", client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", host: "app.example.local"
2026/07/15 17:01:55 [error] 6462#6462: *120 limiting requests, excess: 20.520 by zone "app_rate_limit", client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", host: "app.example.local"
2026/07/15 17:01:55 [error] 6459#6459: *145 limiting requests, excess: 20.480 by zone "app_rate_limit", client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", host: "app.example.local"
2026/07/15 17:01:55 [error] 6459#6459: *137 limiting requests, excess: 20.480 by zone "app_rate_limit", client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", host: "app.example.local"
2026/07/15 17:01:55 [error] 6461#6461: *146 limiting requests, excess: 20.480 by zone "app_rate_limit", client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", host: "app.example.local"
2026/07/15 17:01:55 [error] 6462#6462: *139 limiting requests, excess: 20.460 by zone "app_rate_limit", client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", host: "app.example.local"
2026/07/15 17:01:55 [error] 6460#6460: *147 limiting requests, excess: 20.450 by zone "app_rate_limit", client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", host: "app.example.local"
2026/07/15 17:01:55 [error] 6460#6460: *153 limiting requests, excess: 20.430 by zone "app_rate_limit", client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", host: "app.example.local"
2026/07/15 17:01:55 [error] 6460#6460: *143 limiting requests, excess: 20.420 by zone "app_rate_limit", client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", host: "app.example.local"
2026/07/15 17:01:55 [error] 6459#6459: *154 limiting requests, excess: 20.410 by zone "app_rate_limit", client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", host: "app.example.local"
2026/07/15 17:01:55 [error] 6462#6462: *140 limiting requests, excess: 20.400 by zone "app_rate_limit", client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", host: "app.example.local"
2026/07/15 17:01:55 [error] 6459#6459: *158 limiting requests, excess: 20.370 by zone "app_rate_limit", client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", host: "app.example.local"
2026/07/15 17:01:55 [error] 6459#6459: *156 limiting requests, excess: 20.360 by zone "app_rate_limit", client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", host: "app.example.local"
2026/07/15 17:01:55 [error] 6460#6460: *159 limiting requests, excess: 20.350 by zone "app_rate_limit", client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", host: "app.example.local"
2026/07/15 17:01:55 [error] 6459#6459: *148 limiting requests, excess: 20.350 by zone "app_rate_limit", client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", host: "app.example.local"
2026/07/15 17:01:55 [error] 6460#6460: *160 limiting requests, excess: 20.350 by zone "app_rate_limit", client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", host: "app.example.local"
2026/07/15 17:01:55 [error] 6459#6459: *157 limiting requests, excess: 20.340 by zone "app_rate_limit", client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", host: "app.example.local"
2026/07/15 17:01:55 [error] 6460#6460: *151 limiting requests, excess: 20.340 by zone "app_rate_limit", client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", host: "app.example.local"
2026/07/15 17:01:55 [error] 6459#6459: *155 limiting requests, excess: 20.310 by zone "app_rate_limit", client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", host: "app.example.local"
2026/07/15 17:01:55 [error] 6459#6459: *152 limiting requests, excess: 20.310 by zone "app_rate_limit", client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", host: "app.example.local"
2026/07/15 17:01:55 [error] 6460#6460: *161 limiting requests, excess: 20.280 by zone "app_rate_limit", client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", host: "app.example.local"
```

Ищи строки примерно такого типа: limiting requests, excess ... Это подтверждение, что Nginx реально ограничивал запросы.

---
# 25. Проверка кэша и отказоустойчивость

Выключим все бэкэнды и проверим что nginx возьмет файл при запросе из кэша.

```bash
#Пытаемся запросить тот же файл при выключенных backend-ах
#=========================================================================
dop2@dop2:~$ curl -k -I https://app.example.local/style.css | grep -Ei 'HTTP|cache-control|expires|x-cache-status'
  % Total    % Received % Xferd  Average Speed  Time    Time    Time   Current
                                 Dload  Upload  Total   Spent   Left   Speed
  0     48   0      0   0      0      0      0                              0
HTTP/1.1 200 OK
Expires: Sat, 15 Aug 2026 12:17:02 GMT
Cache-Control: max-age=2592000
Cache-Control: public, max-age=2592000, immutable
X-Cache-Status: HIT #Это хороший знак значит Nginx взял файл из кэша

#=========================================================================

dop2@dop2:~$ curl -k -I https://app.example.local/style.css | grep -Ei 'HTTP|cache-control|expires|x-cache-status'
  % Total    % Received % Xferd  Average Speed  Time    Time    Time   Current
                                 Dload  Upload  Total   Spent   Left   Speed
  0     48   0      0   0      0      0      0           00:04              0
HTTP/1.1 200 OK
Expires: Sat, 15 Aug 2026 12:17:16 GMT
Cache-Control: max-age=2592000
Cache-Control: public, max-age=2592000, immutable
X-Cache-Status: HIT #Это хороший знак значит Nginx взял файл из кэша

#=========================================================================

#Если при включенных сервекрах запросить другой файл, которого нет, то
dop2@dop2:~$ curl -k -I https://app.example.local/style_new.css | grep -Ei 'HTTP|cache-control|expires|x-cache-status'
  % Total    % Received % Xferd  Average Speed  Time    Time    Time   Current
                                 Dload  Upload  Total   Spent   Left   Speed
  0    460   0      0   0      0      0      0                              0
HTTP/1.1 404 File not found #Все норм значит ресурс не найден
Cache-Control: public, max-age=2592000, immutable
X-Cache-Status: MISS
```

Далее из трех backend-ов оставим 2 и посмотрим что все работает и nginx работает с 2умя из трех.
```bash
#ВЫключим backend-1 и проверим что backend-2 и backend-3 работают корректно
dop2@dop2:~$ curl -k https://app.example.local
Hello from backend-2 on port 3002

dop2@dop2:~$ curl -k https://app.example.local
Hello from backend-2 on port 3002

dop2@dop2:~$ curl -k https://app.example.local
Hello from backend-2 on port 3002

dop2@dop2:~$ curl -k https://app.example.local
Hello from backend-3 on port 3003

dop2@dop2:~$ curl -k https://app.example.local
Hello from backend-2 on port 3002

dop2@dop2:~$ curl -k https://app.example.local
Hello from backend-3 on port 3003

dop2@dop2:~$ curl -k https://app.example.local
Hello from backend-2 on port 3002

dop2@dop2:~$ curl -k https://app.example.local
Hello from backend-3 on port 3003

#Провверяем логи и смотрим как ввел себя nginx. Видим ошибки связанные с backend-1 3001 и что nginx заметил backend-1 недоступен.
sudo tail -n 30 /var/log/nginx/app_error.log
2026/07/16 12:26:09 [error] 1591#1591: *3 connect() failed (111: Connection refused) while connecting to upstream, client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", upstream: "http://127.0.0.1:3001/", host: "app.example.local"
2026/07/16 12:26:10 [error] 1592#1592: *6 connect() failed (111: Connection refused) while connecting to upstream, client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", upstream: "http://127.0.0.1:3001/", host: "app.example.local"
2026/07/16 12:26:10 [error] 1589#1589: *9 connect() failed (111: Connection refused) while connecting to upstream, client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", upstream: "http://127.0.0.1:3001/", host: "app.example.local"
2026/07/16 12:26:12 [error] 1589#1589: *18 connect() failed (111: Connection refused) while connecting to upstream, client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", upstream: "http://127.0.0.1:3001/", host: "app.example.local"
2026/07/16 12:26:12 [warn] 1589#1589: *18 upstream server temporarily disabled while connecting to upstream, client: 127.0.0.1, server: app.example.local, request: "GET / HTTP/1.1", upstream: "http://127.0.0.1:3001/", host: "app.example.local"
```

Далее возвращаем backend-1 в работу и проверяем работу отказоустойчивости
```bash
#Небольший цикл с курлом
for i in {1..12}; do curl -k https://app.example.local; done

#Вывод команды. Видим что backend-1 снова заработал и встал в строй с другими backend-ами
dop2@dop2:~$ for i in {1..12}; do curl -k https://app.example.local; done
Hello from backend-3 on port 3003
Hello from backend-2 on port 3002
Hello from backend-1 on port 3001
Hello from backend-3 on port 3003
Hello from backend-2 on port 3002
Hello from backend-1 on port 3001
Hello from backend-2 on port 3002
Hello from backend-3 on port 3003
Hello from backend-1 on port 3001
Hello from backend-2 on port 3002
Hello from backend-3 on port 3003
Hello from backend-1 on port 3001
```

 Почему backend-1 снова появился. У нас было:
```
max_fails=2 fail_timeout=30s
```

Смысл такой:
- backend упал → Nginx временно исключил его
- прошло около 30 секунд → Nginx снова попробовал backend
- backend отвечает → Nginx вернул его в балансировку


---
# 26. Проверка работы access.log

Следующим шагом необходимо проверить access.log для того чтобы понять сработали ли наши настройки:

```bash
#Проверка 20 послоедних строчек app_access.log
sudo tail -n 20 /var/log/nginx/app_access.log

#Вывод команды
dop2@dop2:~$ sudo tail -n 20 /var/log/nginx/app_access.log
[sudo: authenticate] Password:
127.0.0.1 - - [16/Jul/2026:12:26:12 +0000] "GET / HTTP/1.1" 200 34 "-" "curl/8.18.0" rt=0.001 uct=-, 0.000 uht=-, 0.000 urt=0.000, 0.000 upstream=127.0.0.1:3001, 127.0.0.1:3002 #Nginx сначала попробовал backend-1, с ним была проблема, потом переключился на backend-2. Это нормальное поведение для балансировщика.
127.0.0.1 - - [16/Jul/2026:12:26:13 +0000] "GET / HTTP/1.1" 200 34 "-" "curl/8.18.0" rt=0.001 uct=0.000 uht=0.000 urt=0.000 upstream=127.0.0.1:3003
127.0.0.1 - - [16/Jul/2026:12:26:13 +0000] "GET / HTTP/1.1" 200 34 "-" "curl/8.18.0" rt=0.001 uct=0.000 uht=0.000 urt=0.000 upstream=127.0.0.1:3002
127.0.0.1 - - [16/Jul/2026:12:26:13 +0000] "GET / HTTP/1.1" 200 34 "-" "curl/8.18.0" rt=0.001 uct=0.000 uht=0.001 urt=0.001 upstream=127.0.0.1:3003
127.0.0.1 - - [16/Jul/2026:12:26:14 +0000] "GET / HTTP/1.1" 200 34 "-" "curl/8.18.0" rt=0.001 uct=0.000 uht=0.001 urt=0.001 upstream=127.0.0.1:3002
127.0.0.1 - - [16/Jul/2026:12:26:14 +0000] "GET / HTTP/1.1" 200 34 "-" "curl/8.18.0" rt=0.000 uct=0.000 uht=0.001 urt=0.001 upstream=127.0.0.1:3003
127.0.0.1 - - [16/Jul/2026:12:26:14 +0000] "GET / HTTP/1.1" 200 34 "-" "curl/8.18.0" rt=0.001 uct=0.000 uht=0.000 urt=0.000 upstream=127.0.0.1:3002
127.0.0.1 - - [16/Jul/2026:12:32:43 +0000] "GET / HTTP/1.1" 200 34 "-" "curl/8.18.0" rt=0.001 uct=0.000 uht=0.001 urt=0.001 upstream=127.0.0.1:3003
127.0.0.1 - - [16/Jul/2026:12:32:43 +0000] "GET / HTTP/1.1" 200 34 "-" "curl/8.18.0" rt=0.001 uct=0.000 uht=0.001 urt=0.001 upstream=127.0.0.1:3002
127.0.0.1 - - [16/Jul/2026:12:32:43 +0000] "GET / HTTP/1.1" 200 34 "-" "curl/8.18.0" rt=0.024 uct=0.000 uht=0.015 urt=0.024 upstream=127.0.0.1:3001
127.0.0.1 - - [16/Jul/2026:12:32:43 +0000] "GET / HTTP/1.1" 200 34 "-" "curl/8.18.0" rt=0.001 uct=0.000 uht=0.000 urt=0.000 upstream=127.0.0.1:3003
127.0.0.1 - - [16/Jul/2026:12:32:43 +0000] "GET / HTTP/1.1" 200 34 "-" "curl/8.18.0" rt=0.001 uct=0.000 uht=0.001 urt=0.001 upstream=127.0.0.1:3002
127.0.0.1 - - [16/Jul/2026:12:32:43 +0000] "GET / HTTP/1.1" 200 34 "-" "curl/8.18.0" rt=0.000 uct=0.000 uht=0.001 urt=0.001 upstream=127.0.0.1:3001
127.0.0.1 - - [16/Jul/2026:12:32:43 +0000] "GET / HTTP/1.1" 200 34 "-" "curl/8.18.0" rt=0.001 uct=0.000 uht=0.001 urt=0.001 upstream=127.0.0.1:3002
127.0.0.1 - - [16/Jul/2026:12:32:43 +0000] "GET / HTTP/1.1" 200 34 "-" "curl/8.18.0" rt=0.000 uct=0.000 uht=0.001 urt=0.001 upstream=127.0.0.1:3003
127.0.0.1 - - [16/Jul/2026:12:32:43 +0000] "GET / HTTP/1.1" 200 34 "-" "curl/8.18.0" rt=0.001 uct=0.000 uht=0.001 urt=0.001 upstream=127.0.0.1:3001
127.0.0.1 - - [16/Jul/2026:12:32:43 +0000] "GET / HTTP/1.1" 200 34 "-" "curl/8.18.0" rt=0.001 uct=0.000 uht=0.001 urt=0.001 upstream=127.0.0.1:3002
127.0.0.1 - - [16/Jul/2026:12:32:43 +0000] "GET / HTTP/1.1" 200 34 "-" "curl/8.18.0" rt=0.000 uct=0.000 uht=0.000 urt=0.000 upstream=127.0.0.1:3003
127.0.0.1 - - [16/Jul/2026:12:32:43 +0000] "GET / HTTP/1.1" 200 34 "-" "curl/8.18.0" rt=0.000 uct=0.000 uht=0.000 urt=0.000 upstream=127.0.0.1:3001
127.0.0.1 - - [16/Jul/2026:12:44:51 +0000] "HEAD /style_new.css HTTP/1.1" 404 0 "-" "curl/8.18.0" rt=0.001 uct=0.000 uht=0.001 urt=0.001 upstream=127.0.0.1:3002


#Расшифровка 
rt #request_time, общее время обработки запроса Nginx 
uct # upstream_connect_time, время подключения к backend 
uht # upstream_header_time, время до получения заголовков от backend 
urt # upstream_response_time, полное время ответа backend 
upstream # какой backend обработал запрос
```

----
# 27. Создаем logrotate

Теперь надо закрыть пункт. Создать конфигурацию logrotate для nginx логов и посмотрим, есть ли уже стандартный logrotate от Nginx:

```bash
#Проверяем папку стандартную папку с конфигами logrotate. Скорее всего, файл `/etc/logrotate.d/nginx` уже есть.
ls -l /etc/logrotate.d/
#Вывод:
dop2@dop2:~$ ls -l /etc/logrotate.d/
total 72
-rw-r--r-- 1 root root 120 Oct  8  2025 alternatives
-rw-r--r-- 1 root root 126 Nov 12  2024 apport
-rw-r--r-- 1 root root 173 Apr  7 09:02 apt
-rw-r--r-- 1 root root  91 Aug 31  2025 bootlog
-rw-r--r-- 1 root root 130 Jun 22  2020 btmp
-rw-r--r-- 1 root root 160 Feb 13 18:50 chrony
-rw-r--r-- 1 root root 144 Apr 15 19:54 cloud-init-base
-rw-r--r-- 1 root root 112 Oct  8  2025 dpkg
-rw-r--r-- 1 root root  82 Apr 13 13:34 dracut-core
-rw-r--r-- 1 root root 354 Dec 21  2025 fail2ban
-rw-r--r-- 1 root root 329 Mar 27 14:26 nginx
-rw-r--r-- 1 root root 173 Jul 31  2023 postgresql-common
-rw-r--r-- 1 root root 248 Feb 28  2025 rsyslog
-rw-r--r-- 1 root root 126 Jul 13 14:43 ssh-login-alerts
-rw-r--r-- 1 root root 270 Mar 17  2025 ubuntu-pro-client
-rw-r--r-- 1 root root 209 May 16  2023 ufw
-rw-r--r-- 1 root root 235 Mar 27 06:22 unattended-upgrades
-rw-r--r-- 1 root root 145 Jul 26  2021 wtmp

#Проверяем готовый конфиг от nginx проверяем данные файла
sudo cat /etc/logrotate.d/nginx
#Вывод:
dop2@dop2:~$ sudo cat /etc/logrotate.d/nginx
[sudo: authenticate] Password:
/var/log/nginx/*.log {
        daily
        missingok
        rotate 14
        compress
        delaycompress
        notifempty
        create 0640 www-data adm
        sharedscripts
        prerotate
                if [ -d /etc/logrotate.d/httpd-prerotate ]; then \
                        run-parts /etc/logrotate.d/httpd-prerotate; \
                fi \
        endscript
        postrotate
                invoke-rc.d nginx rotate >/dev/null 2>&1
        endscript
}
```

 Мы создадим отдельный аккуратный файл именно для наших логов:
```bash
#Где расположены наши логи
/var/log/nginx/app_access.log
/var/log/nginx/app_error.log

#Создаем файл который будет новвым конфигом для ротации логов
sudo nano /etc/logrotate.d/nginx-app

#Вставляем готовый код
/var/log/nginx/app_access.log /var/log/nginx/app_error.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 0640 www-data adm
    sharedscripts
    postrotate
        [ -s /run/nginx.pid ] && kill -USR1 $(cat /run/nginx.pid)
    endscript
}

#Коротко что это значит:
#============================================================================
daily # проверять ротацию ежедневно
rotate 14 # хранить 14 старых логов
compress # сжимать старые логи
delaycompress # сжимать не сразу, а со следующей ротации
missingok # не падать, если файла нет
notifempty # не ротировать пустой лог
create # создать новый лог с нужными правами
postrotate # сказать Nginx переоткрыть лог-файлы
[ -s /run/nginx.pid ] && kill -USR1 $(cat /run/nginx.pid)
#Разбор
1. [ -s /run/nginx.pid ] # Флаг `-s` проверяет: _«Существует ли файл `/run/nginx.pid` и имеет ли он размер больше 0 байт?»_. В этом файле Nginx хранит PID (идентификатор своего главного процесса) в виде обычного числа (например, `1234`). Если файл есть и не пустой, значит, Nginx сейчас запущен.
2. && # Логическое «И». Переводится как: _«Если прошлое действие успешно (файл существует и не пуст), то выполняй то, что идет дальше»_.
3. kill -USR1 ... # Утилита `kill` не обязательно убивает процесс. Её главная задача — отправить процессу системный сигнал. Сигнал `-USR1` (User-defined signal 1) для Nginx зашит разработчиками как команда: _«Не останавливая работу, закрой старые дескрипторы файлов логов и открой их заново»_.
4. $(cat /run/nginx.pid) # Конструкция $(...) берет результат выполнения команды внутри скобок и подставляет его в основную команду. Команда `cat` просто читает число (PID) из файла. Если в файле было число `1234`, то вся правая часть превратится в: `kill -USR1 1234`.
#============================================================================
```

---
# 28.  Проверяем logrotate без реальной ротации

```bash
#Проверка на ошибки через debug mode но чтобы ничего не менялось. `-d` означает debug mode
sudo logrotate -d /etc/logrotate.d/nginx-app

#Потом можно сделать принудительный тест:
sudo logrotate -f /etc/logrotate.d/nginx-app

#Проверяем:
ls -lh /var/log/nginx/app_*
#Вывод:
dop2@dop2:~$ ls -lh /var/log/nginx/app_*
-rw-r----- 1 www-data adm    0 Jul 16 14:41 /var/log/nginx/app_access.log
-rw-r--r-- 1 www-data root 20K Jul 16 13:22 /var/log/nginx/app_access.log.1
-rw-r----- 1 www-data adm    0 Jul 16 14:41 /var/log/nginx/app_error.log
-rw-r--r-- 1 www-data root 14K Jul 16 12:26 /var/log/nginx/app_error.log.1
```

---
# 29. Проверяем так же доступ извне нашего сервера 

Если решим попробовать сразу, как на нашем сервере можем столкнуться с 2мя ошибками. 
- Первая, это то, что у нас есть настройки в iptables которые дропают ввходящие запросы на порты 80 443
- И то что наш компьютер не знает что IP 192.168.31.179 -> app.example.local
```bash
#возможная ошибка
PS C:\Users\skame> curl.exe -I http://app.example.local
curl: (6) Could not resolve host: app.example.local
PS C:\Users\skame> curl.exe -k https://app.example.local
curl: (6) Could not resolve host: app.example.local
PS C:\Users\skame> curl.exe -I http://app.example.local
curl: (6) Could not resolve host: app.example.local
PS C:\Users\skame> curl.exe -I http://app.example.local
curl: (6) Could not resolve host: app.example.local

```

Для того чтобы проверить например с нашей основной машинки на виндовс нам надо внести некоторые изменения в наш конфиг iptables, которые мы вносили в нашу прошлую работу [[Jump host]] .

```bash
#Идем в наш конфиг apply-jumphost-iptables.sh
sudo nano ~/jumphost-backups/iptables/apply-jumphost-iptables.sh

#Вставляем эти строчки после настройки по SSH
# HTTP/HTTPS к Nginx только с Windows
iptables -A INPUT -p tcp -s "$WEB_ALLOWED_IP" --dport 80 \ 
  -m conntrack --ctstate NEW \ 
  -j ACCEPT 
iptables -A INPUT -p tcp -s "$WEB_ALLOWED_IP" --dport 443 \ 
  -m conntrack --ctstate NEW \ 
  -j ACCEPT

#Дополнительно делаем эту строку после 6 пункта dns
# 6.1 Разрешить NTP для синхронизации времени
iptables -A OUTPUT -p udp --dport 123 -j ACCEPT


#Вот что получилось:
#=========================================================================
#!/usr/bin/env bash
set -euo pipefail

SSH_PORT="2222"
ALLOWED_SSH_IP="192.168.31.150"
PRIVATE_NET="192.168.56.0/24"
WEB_ALLOWED_IP="192.168.31.150"

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

# HTTP/HTTPS к Nginx только с Windows
iptables -A INPUT -p tcp -s "$WEB_ALLOWED_IP" --dport 80 \
  -m conntrack --ctstate NEW \
  -j ACCEPT

iptables -A INPUT -p tcp -s "$WEB_ALLOWED_IP" --dport 443 \
  -m conntrack --ctstate NEW \
  -j ACCEPT

# 5. Всё лишнее на SSH логируем и дропаем
iptables -A INPUT -p tcp --dport "$SSH_PORT" \
  -m limit --limit 5/min \
  -j LOG --log-prefix "IPTABLES SSH DROP: " --log-level 4

iptables -A INPUT -p tcp --dport "$SSH_PORT" -j DROP

# 6. Разрешить DNS-запросы с jump host
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

# 6.1 Разрешить NTP для синхронизации времени
iptables -A OUTPUT -p udp --dport 123 -j ACCEPT

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

На основной машинке нужно будет в файл hosts внести наш ip и имя, так как Windows не знает, какой IP соответствует `app.example.local`.

```bash
#Заходим в наш hosts на пк C:\Windows\System32\drivers\etc\hosts и вставляем строчку
192.168.31.179 app.example.local

#Проверяем с другого терминала
PS C:\Users\skame> curl.exe -I http://app.example.local
HTTP/1.1 301 Moved Permanently
Server: nginx
Date: Thu, 16 Jul 2026 16:08:14 GMT
Content-Type: text/html
Content-Length: 162
Connection: keep-alive
Location: https://app.example.local/
#========================================================================
PS C:\Users\skame> curl.exe -k https://app.example.local
Hello from backend-2 on port 3002

PS C:\Users\skame> curl.exe -k https://app.example.local
Hello from backend-1 on port 3001

PS C:\Users\skame> curl.exe -k https://app.example.local
Hello from backend-3 on port 3003
```

