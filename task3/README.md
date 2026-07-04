Задание 2. System timer

## 1. Пользователь

Можно создать нового пользователя, а можно использовать существующего. Если создавать нового то есть несколько способов:

```bash
#Создание системного пользователя без домашнего каталога
sudo useradd -r -s /usr/sbin/nologin -M <user_name>

#Если нужен каталог для конфигов
sudo useradd -r -s /usr/sbin/nologin -m -d /var/lib/myapp myappuser
```

## 2. Скрипт

Далее создаем скрипт-файл который мы будем запускать раз в определенный период (/opt/scripts/cleanup.sh):

```bash
#Создаем папку и файл в который записываем скрипт
sudo mkdir /opt/scripts && sudo nano /opt/scripts/cleanup.sh

#Скрипт:
#!/bin/bash
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Cleanup running" >> /var/log/cleanup.log

#Даем нашему скрипту права на запуск
sudo chmod +x /opt/scripts/cleanup.sh

#Меняем права и если у н ас будет от другого пользователя, то даем права на запись
sudo chown unnamed:root /var/log/cleanup.log
```

## 3. Создание unit файла и timer файла

```bash
#Unit-файл
[Unit]
Description=Log Creater

[Service]
Type=oneshot
User=unnamed
WorkingDirectory=/opt/scripts
ExecStart=/opt/scripts/cleanup.sh

[Install]
WantedBy=multi-user.target

#Timer-файл
[Unit]
Decription=Every 2 min log

[Timer]
Type=oneshot
OnCalendar=*-*-* *:0/2
Presistent=true

[Install]
WantedBy=timers.target

#Смотрим статусы
systemctl status cleanup.timer

systemctl status cleanup.service

#Далее проверяем Unit-файл
systemd-analyze verify /etc/systemd/system/cleanup.srvice

#Так же проверяем Timer-файл
systemd-analyze verify /etc/systemd/system/cleanup.timer

#Релоудим демона
systemctl daemon-reload

#Включаем наш таймер
sudo systemctl enable --now cleanup.timer
```

## Итоги: 

```bash
dop2@dop2:/$ systemctl list-timers | grep cleanup && cat /var/log/cleanup.log
Sat 2026-07-04 22:46:00 UTC 1min 35s Sat 2026-07-04 22:44:23 UTC       1s ago cleanup.timer                  cleanup.service
[2026-07-04 22:16:10] Cleanup running
[2026-07-04 22:16:38] Cleanup running
[2026-07-04 22:24:31] Cleanup running
[2026-07-04 22:26:24] Cleanup running
[2026-07-04 22:28:18] Cleanup running
[2026-07-04 22:30:02] Cleanup running
[2026-07-04 22:32:29] Cleanup running
[2026-07-04 22:34:04] Cleanup running
[2026-07-04 22:36:31] Cleanup running
[2026-07-04 22:38:22] Cleanup running
[2026-07-04 22:40:02] Cleanup running
[2026-07-04 22:42:30] Cleanup running
[2026-07-04 22:44:23] Cleanup running
```
