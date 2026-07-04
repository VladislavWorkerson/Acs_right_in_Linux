# Создал первый unit файл

## 1. Для начала был создан безликий системный пользователь:

```bash
#Создание системного пользователя без домашнего каталога
sudo useradd -r -s /usr/sbin/nologin -M myappuser

#Если нужен каталог для конфигов
sudo useradd -r -s /usr/sbin/nologin -m -d /var/lib/myapp myappuser
```


## 2. Далее создаем директорию, запускаемый скрипт и unit файл:

```bash
#Создаем папку и исполняемый скрипт внутри
sudo mkdir /opt/simple-web && sudo nano /opt/simple-web/service.py

#После того как написали скрипт идем в etc/systemd/system/ для создания unit создаем и сохраняем
[Unit]
Description=Siomple-web homework

[Service]
Type=simple
User=unnamed
WorkingDirectory=/opt/simple-web
ExecStart=/opt/simple-web/server.py
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi.user.target
```

## 3. Запуск и проверка unit файла

```bash
#Перед тем как сделать reload можно проверить наш файл. Если нет ощибок идем дальше
systemd-analyze verify /etc/systemd/system/simple-web.service

#Далее релоудим демона
systemctl daemon-reload

#Затем включаем сервис и включаем чтоб он был всегда при запуске
sudo systemctl enable --now simple-web.service

#Проверяем что все работает 
systemctl status simple-web.service
```

## Итого:

```bash
dop2@dop2:/$ systemctl status simple-web.service && curl http://localhost:8080/
● simple-web.service - Siomple-web homework
     Loaded: loaded (/etc/systemd/system/simple-web.service; enabled; preset: enabled)
     Active: active (running) since Sat 2026-07-04 19:37:23 UTC; 17s ago
 Invocation: 47662ce6400f4cfe9790bfb7c55d04ee
   Main PID: 5262 (python3)
      Tasks: 1 (limit: 3968)
     Memory: 9.4M (peak: 9.8M)
        CPU: 36ms
     CGroup: /system.slice/simple-web.service
             └─5262 python3 /opt/simple-web/server.py
Hello from systemd service!


dop2@dop2:/$ ps aux | grep 5262
unnamed     5262  0.0  0.3  33208 19932 ?        Ss   19:37   0:00 python3 /opt/simple-web/server.py
dop2        5310  0.0  0.0   6716  2616 pts/0    S+   19:37   0:00 grep --color=auto 5262

dop2@dop2:/$ ps -u unnamed -f
UID          PID    PPID  C STIME TTY          TIME CMD
unnamed     5262       1  0 19:37 ?        00:00:00 python3 /opt/simple-web/server.py
```
