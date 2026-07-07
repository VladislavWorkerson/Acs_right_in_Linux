# 1. Вот шаги установки и настройки fail2ban для sshd

```bash
#Устанавливаем fail2ban
sudo apt install -y fail2ban

#Проверка статуса fail2ban
systemctl status fail2ban

#Вывод проверки статуса
dop2@dop2:/$ systemctl status fail2ban
● fail2ban.service - Fail2Ban Service
     Loaded: loaded (/usr/lib/systemd/system/fail2ban.service; enabled; preset: enabled)
     Active: active (running) since Mon 2026-07-06 12:27:13 UTC; 7min ago
 Invocation: e48526ecd5644d9191faab40a195a0dd
       Docs: man:fail2ban(1)
   Main PID: 4531 (fail2ban-server)
      Tasks: 5 (limit: 3971)
     Memory: 14.9M (peak: 19.3M)
        CPU: 564ms
     CGroup: /system.slice/fail2ban.service
             └─4531 /usr/bin/python3 /usr/bin/fail2ban-server -xf start



#Пишем конфиг в файл jail.local который будет поверх jail.conf(этот файл менять нельзя), можно только jail.local
sudo nano /etc/fail2ban/jail.local

#Далее пишем наш конфиг (Пока что только для ssh)
[DEFAULT]
bantime = 1h #Время на сколько бан
findtime = 10m #Промежуток времени в котором считается неудачные попытки
maxretry = 3 #Количество неудачных попыток
#Пока коммент, для тестов
#ignoreip = 127.0.0.1/8 192.168.31.150 #Белый список адресов
#destemail = your-email@example.com #Куда отправляется email сообщение
#sender = fail2ban@yourserver.com #Кто отправляет сообщение
#action = %(action_mwl)s 

[sshd]
enabled = true #Клетка влючена(Если false значит выключена)
port = ssh #Оставляем как есть не меняли порт
filter = sshd #Сам fail2ban предоставляет фильтры в /etc/fail2ban/filter.d/
logpath = /var/log/auth.log #Путь к лог-файлу? fail2ban будет мониторить
maxretry = 3
bantime = 1h
findtime = 10m

#Далее перезапускаем наш fail2ban 
sudo systemctl restart fail2ban

#Проверяем наш статус клетки для ssh
sudo fail2ban-client status sshd

#Пробуем с другого компьютера подключиться и вводим не правильно 3 раза пароль
#До неудачных попыток
dop2@dop2:/$ sudo fail2ban-client status sshd
Status for the jail: sshd
|- Filter
|  |- Currently failed: 0
|  |- Total failed:     0
|  `- Journal matches:  _SYSTEMD_UNIT=ssh.service + _COMM=sshd
`- Actions
   |- Currently banned: 0
   |- Total banned:     0
   `- Banned IP list:
   
#После неудачных попыток
dop2@dop2:/$ sudo fail2ban-client status sshd
Status for the jail: sshd
|- Filter
|  |- Currently failed: 0
|  |- Total failed:     3
|  `- Journal matches:  _SYSTEMD_UNIT=ssh.service + _COMM=sshd
`- Actions
   |- Currently banned: 1
   |- Total banned:     1
   `- Banned IP list:   192.168.31.102 #Видим ip адрес нашей второй машинкм в бане.

#Так же можно забанить вручную 
sudo fail2ban-client set sshd banip 192.168.31.102

#И вручную разбанить
sudo fail2ban-client set sshd unbanip 192.168.31.102
```

# 2. Настройка почтового сообщения от fail2ban

```bash
#Устанавливаем postfix для отправки сообщений по почте
sudo apt install postfix mailutils -y
#Далее выбираем "Internet Site" (или "Satellite system") и можешь оставить имя сервера по умолчанию 

#Проверяем наш postfix сервис 
sudo systemctl status postfix
#Вывод команды
dop2@dop2:/$ sudo systemctl status postfix
● postfix.service - Postfix Mail Transport Agent (main/default instance)
     Loaded: loaded (/usr/lib/systemd/system/postfix.service; enabled; preset: enabled)
     Active: active (running) since Mon 2026-07-06 12:20:52 UTC; 58min ago
 Invocation: 5f6d5918988645ae957794170c5076f0
       Docs: man:postfix(1)
    Process: 4258 ExecStartPre=postfix check (code=exited, status=0/SUCCESS)
    Process: 4409 ExecStart=postfix debian-systemd-start (code=exited, status=0/SUCCESS)
   Main PID: 4417 (master)
      Tasks: 3 (limit: 3971)
     Memory: 3.5M (peak: 4.6M)
        CPU: 501ms
     CGroup: /system.slice/postfix.service
             ├─4417 /usr/lib/postfix/sbin/master -w
             ├─4418 pickup -l -t unix -u
             └─4420 qmgr -l -t unix -u

```

Подготовка почты для отправки:
Нельзя использовать обычный пароль от Яндекс.Почты! Нужно создать **пароль приложения**.

1. Зайди на https://id.yandex.ru/security
2. Найди раздел **"Пароли приложений"**
3. Нажми **"Создать пароль"**
4. Выбери тип: **"Почта"**
5. Придумай название (например, `postfix`)
6. Скопируй сгенерированный пароль (он будет вида `abcdefghijklmnop`)
**Сохрани этот пароль** — он понадобится дальше


```bash
#Идем редактировать конфиг для нашего posfix
sudo nano /etc/postfix/main.cf

#Вот такой файл у нас получился main.cf
#======== START =============
# See /usr/share/postfix/main.cf.dist for a commented, more complete version

# See http://www.postfix.org/COMPATIBILITY_README.html
compatibility_level = 3.9

# Which domain that locally-originated mail appears to come from.
# Debian policy suggests to read this value from /etc/mailname.
#XX needs a review in postinst&config
#myorigin = /etc/mailname
#myorigin = $mydomain
myorigin = $myhostname

# Text that follows the 220 code in the SMTP server's greeting banner.
# You MUST specify $myhostname at the start due to an RFC requirement.
smtpd_banner = $myhostname ESMTP $mail_name (Ubuntu)

# IP protocols to use: ipv4, ipv6, or all
# (set this explicitly so `post-install upgrade-configuration' wont complain)
inet_protocols = ipv4

# List of "trusted" SMTP clients (maptype:mapname allowed) that have more
# privileges than "strangers".  If mynetworks is not specified (the default),
# mynetworks_style is used to compute its value.
#mynetworks_style = class
#mynetworks_style = subnet
mynetworks_style = host
#
mynetworks = 127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128

# Uncomment the next line to generate "delayed mail" warnings
#delay_warning_time = 4h

# List of domains (maptype:mapname allowed) that this machine considers
# itself the final destination for.
mydestination = $myhostname, localhost

# Maximum size of a user mailbox
mailbox_size_limit = 0

# Optional external command to use instead of mailbox delivery.  If set,
# you must set up an alias to forward root mail to a real user.
#mailbox_command = /usr/bin/procmail
#mailbox_command = /usr/bin/procmail -a "$EXTENSION"
mailbox_command =

# List of alias maps to use to lookup local addresses.
# Per Debian Policy it should be /etc/aliases.
alias_maps = hash:/etc/aliases

# List of alias maps to make indexes on, when running newaliases.
alias_database = hash:/etc/aliases

# Notify (or not) local biff service when new mail arrives.
# Rarely used these days.
biff = no

# Separator between user name and address extension (user+foo@domain)
#recipient_delimiter = +
recipient_delimiter = +

# A host to send "other" mail to
#relayhost = $mydomain
#relayhost = [gateway.example.com]
#relayhost = [ip.add.re.ss]:port
#relayhost = uucphost
relayhost = [smtp.yandex.ru]:587

# Where to look for Cyrus SASL configuration files.  Upstream default is unset
# (use compiled-in SASL library default), Debian Policy says it should be
# /etc/postfix/sasl.
cyrus_sasl_config_path = /etc/postfix/sasl

# SMTP server RSA key and certificate in PEM format
smtpd_tls_key_file = /etc/ssl/private/ssl-cert-snakeoil.key
smtpd_tls_cert_file = /etc/ssl/certs/ssl-cert-snakeoil.pem
# SMTP Server security level: none|may|encrypt
smtpd_tls_security_level = encrypt

# List of CAs for SMTP Client to trust
# Prefer this over _CApath when smtp is running chrooted
smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt
# SMTP Client TLS security level: none|may|encrypt|...
smtp_tls_security_level = may
# SMTP Client TLS session cache
smtp_tls_session_cache_database = btree:${data_directory}/smtp_scache
smtpd_relay_restrictions = permit_mynetworks permit_sasl_authenticated defer_unauth_destination
myhostname = dop2.local
inet_interfaces = all

# Аутентификация SASL
#smtp_use_tls = yes
smtp_sasl_auth_enable = yes
smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd
smtp_sasl_security_options = noanonymous
smtputf8_enable = no
#========== END ===========
# Переписывание локальных адресов на реальный email
sender_canonical_maps = hash:/etc/postfix/generic

#Проверка отправки письма на почту самому себе
echo "test 100" | mail -s "test101" greedyrpper@yandex.ru

#Проверка логов отправки письма (Видим status=sent)
sudo tail -f /var/log/mail.log

2026-07-07T10:25:55.110666+00:00 dop2 postfix/qmgr[1649]: D44074B0B9: removed
2026-07-07T10:25:55.637658+00:00 dop2 postfix/smtp[2631]: 134184B4E8: to=<greedyrpper@yandex.ru>, relay=smtp.yandex.ru[77.88.21.158]:587, delay=601, delays=599/0.51/0.18/0.42, dsn=2.0.0, status=sent (250 2.0.0 Ok: queued on mail-nwsmtp-smtp-production-main-64.vla.yp-c.yandex.net 1783419955-tPFHe55kViE0-EXc4x7wE)
2026-07-07T10:25:55.639279+00:00 dop2 postfix/qmgr[1649]: 134184B4E8: removed
2026-07-07T10:25:55.815428+00:00 dop2 postfix/smtp[2632]: DA8E645F15: to=<greedyrpper@yandex.ru>, relay=smtp.yandex.ru[77.88.21.158]:587, delay=55839, delays=55837/0.04/0.17/1.1, dsn=2.0.0, status=sent (250 2.0.0 Ok: queued on mail-nwsmtp-smtp-production-main-80.klg.yp-c.yandex.net 1783419955-sPFB9a6dK0U0-ZSZjGRT4)
2026-07-07T10:25:55.816437+00:00 dop2 postfix/qmgr[1649]: DA8E645F15: removed
2026-07-07T10:26:04.938951+00:00 dop2 postfix/pickup[1648]: E523045F11: uid=1000 from=<dop2@dop2>
2026-07-07T10:26:04.939619+00:00 dop2 postfix/cleanup[2647]: E523045F11: message-id=<20260707102604.E523045F11@dop2.local>
2026-07-07T10:26:04.942599+00:00 dop2 postfix/qmgr[1649]: E523045F11: from=<greedyrpper@yandex.ru>, size=333, nrcpt=1 (queue active)
2026-07-07T10:26:05.794815+00:00 dop2 postfix/smtp[2634]: E523045F11: to=<greedyrpper@yandex.ru>, relay=smtp.yandex.ru[77.88.21.158]:587, delay=0.86, delays=0.01/0/0.17/0.68, dsn=2.0.0, status=sent (250 2.0.0 Ok: queued on mail-nwsmtp-smtp-production-main-81.klg.yp-c.yandex.net 1783419965-4QFq3w6gGuQ0-nHUNJbrU)
2026-07-07T10:26:05.795813+00:00 dop2 postfix/qmgr[1649]: E523045F11: removed

#==========Дополнительыне полезные команды с письмами============

# Посмотреть очередь
sudo mailq

# Очистить всю очередь
sudo postsuper -d ALL
```

# 3. Далее настраиваем jail.local для (nginx, postgresql)

```bash
#Заходим в наш jail и настраиваем для nginx posgresql
sudo nano /etc/fail2ban/jail.local

[DEFAULT]
# Глобальные настройки по умолчанию
bantime = 1h
findtime = 10m
maxretry = 3
#ignoreip = 127.0.0.1/8 192.168.31.150
#destemail = greedyrpper@yandex.ru
#sender = greedyrpper@yandex.ru
#action = %(action_mwl)s
# Указываем fail2ban использовать наш кастомный сценарий
action = iptables-custom

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 1h
findtime = 10m

[nginx-http-auth]
enabled  = true
port     = http,https
filter   = nginx-auth
logpath  = /var/log/nginx/access.log
maxretry = 10
findtime = 1m
bantime  = 30m

[postgresql]
enabled  = true
port     = 5432
filter   = postgresql
logpath  = /var/log/postgresql/postgresql-18-main.log
maxretry = 5
findtime = 300
bantime  = 7200

dop2@dop2:/$ sudo fail2ban-client status postgresql
Status for the jail: postgresql
|- Filter
|  |- Currently failed: 0
|  |- Total failed:     0
|  `- File list:        /var/log/postgresql/postgresql-18-main.log
`- Actions
   |- Currently banned: 1
   |- Total banned:     1
   |- Banned IP list:   192.168.31.181


dop2@dop2:/$ sudo fail2ban-client status nginx-http-auth
Status for the jail: nginx-http-auth
|- Filter
|  |- Currently failed: 0
|  |- Total failed:     0
|  `- File list:        /var/log/nginx/access.log
`- Actions
   |- Currently banned: 0
   |- Total banned:     0
   `- Banned IP list:
```

# 4. Настройка перманентных банов

Для этого нам поможет recidive

```bash
#Заходим в наш jail и настраиваем пермонентные баны
sudo nano /etc/fail2ban/jail.local

# Конечный файл с нашими настройками jail
[DEFAULT]
# Глобальные настройки по умолчанию
bantime = 1h
findtime = 10m
maxretry = 3
#ignoreip = 127.0.0.1/8 192.168.31.150
#destemail = greedyrpper@yandex.ru
#sender = greedyrpper@yandex.ru
#action = %(action_mwl)s
# Указываем fail2ban использовать наш кастомный сценарий
action = iptables-custom

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 1h
findtime = 10m

[nginx-http-auth]
enabled  = true
port     = http,https
filter   = nginx-auth
logpath  = /var/log/nginx/access.log
maxretry = 10
findtime = 1m
bantime  = 30m

[postgresql]
enabled  = true
port     = 5432
filter   = postgresql
logpath  = /var/log/postgresql/postgresql-18-main.log
maxretry = 5
findtime = 300
bantime  = 7200

[recidive]
enabled  = true
filter   = recidive
logpath  = /var/log/fail2ban.log
bantime  = 315360000
findtime = 1209600
maxretry = 3
action = ip-blocklist

#Видим наши забаненные ip на 10 лет
dop2@dop2:/$ sudo fail2ban-client status recidive
Status for the jail: recidive
|- Filter
|  |- Currently failed: 7
|  |- Total failed:     19
|  `- File list:        /var/log/fail2ban.log
`- Actions
   |- Currently banned: 2
   |- Total banned:     2
   |- Banned IP list:   192.168.31.102 192.168.31.103

#Непереживаем их можно разбанить с помощью команды
sudo fail2ban-client set recidive unbanip 192.168.31.102

#Так же можем забанить руками
sudo fail2ban-client set recidive banip 192.168.31.102

#Далее нам необходимо создать conf файл с тем чтобы сохранить наши IP и сам файл с ip 
sudo nano /etc/fail2ban/action.d/ip-blocklist.conf
#Пишем в него конфиг
[Definition]
actionstart = 
    iptables -N FAIL2BAN-PERM 2>/dev/null || true
    iptables -I INPUT -j FAIL2BAN-PERM 2>/dev/null || true
    [ -f /etc/fail2ban/ip.blocklist ] && while read IP; do
        [ -n "$IP" ] && iptables -I FAIL2BAN-PERM 1 -s $IP -j LOG --log-prefix "FAIL2BAN-PERM: " --log-level 4
        [ -n "$IP" ] && iptables -I FAIL2BAN-PERM 2 -s $IP -j DROP
    done < /etc/fail2ban/ip.blocklist
actionstop = 
    iptables -L FAIL2BAN-PERM -n | grep DROP | awk '{print $4}' | sort -u > /etc/fail2ban/ip.blocklist
    iptables -D INPUT -j FAIL2BAN-PERM 2>/dev/null || true
    iptables -F FAIL2BAN-PERM 2>/dev/null || true
    iptables -X FAIL2BAN-PERM 2>/dev/null || true
actionban = 
    iptables -I FAIL2BAN-PERM 1 -s <ip> -j LOG --log-prefix "FAIL2BAN-PERM: " --log-level 4
    iptables -I FAIL2BAN-PERM 2 -s <ip> -j DROP
    echo "<ip>" >> /etc/fail2ban/ip.blocklist
actionunban = 
    iptables -D FAIL2BAN-PERM -s <ip> -j LOG 2>/dev/null || true
    iptables -D FAIL2BAN-PERM -s <ip> -j DROP 2>/dev/null || true
    sed -i "/<ip>/d" /etc/fail2ban/ip.blocklist

#Создаем файл в котором будут хранится ip и которые будут использоваться после перезапуска
sudo nano /etc/fail2ban/ip.blocklist

```


# 5. Далее был настроен мониторинг

```bash
#Создаем исполняемый скрипт для того чтобы выводить простую статистику по банам сервисов
sudo nano /usr/local/bin/fail2ban-stats.sh 

#Вот скрипт для получения статистики
#!/bin/bash

CB_SSH=$(sudo fail2ban-client status sshd | grep "Currently banned" | awk '{print $4}')
TB_SSH=$(sudo fail2ban-client status sshd | grep "Total banned" | awk '{print $4}')
CB_NGINX=$(sudo fail2ban-client status nginx-http-auth | grep "Currently banned" | awk '{print $4}')
TB_NGINX=$(sudo fail2ban-client status nginx-http-auth | grep "Total banned" | awk '{print $4}')
CB_PGSQL=$(sudo fail2ban-client status postgresql | grep "Currently banned" | awk '{print $4}')
TB_PGSQL=$(sudo fail2ban-client status postgresql | grep "Total banned" | awk '{print $4}')

# Если какие-то значения пустые, заменяем на 0
CB_SSH=${CB_SSH:-0}
TB_SSH=${TB_SSH:-0}
CB_NGINX=${CB_NGINX:-0}
TB_NGINX=${TB_NGINX:-0}
CB_PGSQL=${CB_PGSQL:-0}
TB_PGSQL=${TB_PGSQL:-0}

# Складываем числа (используем арифметику bash)
TOTAL_CB=$((CB_SSH + CB_NGINX + CB_PGSQL))
TOTAL_TB=$((TB_SSH + TB_NGINX + TB_PGSQL))

# Выводим статистику
echo "=== Fail2Ban Statistics ==="
echo "Jail: sshd | Currently banned: $CB_SSH | Total banned: $TB_SSH"
echo "Jail: nginx-auth | Currently banned: $CB_NGINX | Total banned: $TB_NGINX"
echo "Jail: postgresql | Currently banned: $CB_PGSQL | Total banned: $TB_PGSQL"
echo "==========================="
echo "Total currently banned: $TOTAL_CB"
echo "Total banned all time: $TOTAL_TB"

#Далее обязательно делаем файл исполняемым
sudo chmod +x /usr/local/bin/fail2ban-stats.sh 

#Проверяем скрипт
dop2@dop2:/usr/local/bin$ fail2ban-stats.sh
=== Fail2Ban Statistics ===
Jail: sshd | Currently banned: 2 | Total banned: 2
Jail: nginx-auth | Currently banned: 0 | Total banned: 0
Jail: postgresql | Currently banned: 0 | Total banned: 0
===========================
Total currently banned: 2
Total banned all time: 2


#Создаем скрипт для того чтобы выгрузить метрики в различные файлы (json, csv)
sudo nano /usr/local/bin/fail2ban-export.sh

#Далее обязательно делаем файл исполняемым
sudo chmod +x /usr/local/bin/fail2ban-export.sh

#Вывод данных в файлах
dop2@dop2:/usr/local/bin$ cat /var/log/fail2ban-metrics.csv
timestamp,jail,currently_banned,total_banned
2026-07-07 13:14:51,sshd,0,2
2026-07-07 13:18:29,sshd,0,2
2026-07-07 13:18:29,nginx,0,1
2026-07-07 13:18:29,postgresql,0,0
2026-07-07 13:22:28,sshd,0,2
2026-07-07 13:22:28,nginx,0,1
2026-07-07 13:22:28,postgresql,0,0
2026-07-07 13:23:12,sshd,3,5
2026-07-07 13:23:12,nginx,0,1
2026-07-07 13:23:12,postgresql,0,0
2026-07-07 13:49:46,sshd,3,5
2026-07-07 13:49:46,nginx,0,1
2026-07-07 13:49:46,postgresql,0,0
2026-07-07 13:51:38,sshd,3,5
2026-07-07 13:51:38,nginx,0,1
2026-07-07 13:51:38,postgresql,0,0
2026-07-07 13:52:08,sshd,3,5
2026-07-07 13:52:08,nginx,0,1
2026-07-07 13:52:08,postgresql,0,0
2026-07-07 14:35:19,sshd,0,5
2026-07-07 14:35:19,nginx,0,1
2026-07-07 14:35:19,postgresql,0,0

dop2@dop2:/usr/local/bin$ cat /var/log/fail2ban-metrics.json
{
  "timestamp": "2026-07-07 14:35:19",
  "jails": {
    "sshd": {"currently_banned": 0, "total_banned": 5},
    "nginx-auth": {"currently_banned": 0, "total_banned": 1},
    "postgresql": {"currently_banned": 0, "total_banned": 0}
  },
  "totals": {
    "currently_banned": 0,
    "total_banned": 6
  }
}

#Далее настраиваем ежедневный репорт на почут через крон (добавили тестово только его каждые две минуты)
#Создаем скрипт файл который станет телом сообщения на почту и который будет отправлять сообщение на почту
sudo nano /usr/local/bin/fail2ban-report.sh

#Даем права на запуск
sudo chmod +x /usr/local/bin/fail2ban-report.sh

#Добавляем скрипт
#!/bin/bash


#collect all data
CB_SSH=$(sudo fail2ban-client status sshd | grep "Currently banned" | awk '{print $4}')
TB_SSH=$(sudo fail2ban-client status sshd | grep "Total banned" | awk '{print $4}')
CB_NGINX=$(sudo fail2ban-client status nginx-http-auth | grep "Currently banned" | awk '{print $4}')
TB_NGINX=$(sudo fail2ban-client status nginx-http-auth | grep "Total banned" | awk '{print $4}')
CB_PGSQL=$(sudo fail2ban-client status postgresql | grep "Currently banned" | awk '{print $4}')
TB_PGSQL=$(sudo fail2ban-client status postgresql | grep "Total banned" | awk '{print $4}')
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')


# Если какие-то значения пустые, заменяем на 0
CB_SSH=${CB_SSH:-0}
TB_SSH=${TB_SSH:-0}
CB_NGINX=${CB_NGINX:-0}
TB_NGINX=${TB_NGINX:-0}
CB_PGSQL=${CB_PGSQL:-0}
TB_PGSQL=${TB_PGSQL:-0}

# Складываем числа (используем арифметику bash)
TOTAL_CB=$((CB_SSH + CB_NGINX + CB_PGSQL))
TOTAL_TB=$((TB_SSH + TB_NGINX + TB_PGSQL))


# Создаем переменную с телом письма
REPORT="Привет! Вот сводка по безопасности за сегодня:\n\n"
REPORT+="=== SSH ===\n"
REPORT+="Текущие баны: $CB_SSH\n"
REPORT+="Всего банов: $TB_SSH\n\n"
REPORT+="=== NGINX ===\n"
REPORT+="Текущие баны: $CB_NGINX\n"
REPORT+="Всего банов: $TB_NGINX\n\n"
REPORT+="=== PGSQL ===\n"
REPORT+="Текущие баны: $CB_PGSQL\n"
REPORT+="Всего банов: $TB_PGSQL\n\n"


echo -e "$REPORT" | mail -s "Report" greedyrpper@yandex.ru


#Настройка крона на отправку сообщения каждый 5 минут
dop2@dop2:/$ sudo crontab -e
no crontab for root - using an empty one
crontab: installing new crontab
dop2@dop2:/$ crontab -l
no crontab for dop2
dop2@dop2:/$ sudo crontab -l
# Edit this file to introduce tasks to be run by cron.
#
# Each task to run has to be defined through a single line
# indicating with different fields when the task will be run
# and what command to run for the task
#
# To define the time you can provide concrete values for
# minute (m), hour (h), day of month (dom), month (mon),
# and day of week (dow) or use '*' in these fields (for 'any').
#
# Notice that tasks will be started based on the cron's system
# daemon's notion of time and timezones.
#
# Output of the crontab jobs (including errors) is sent through
# email to the user the crontab file belongs to (unless redirected).
#
# For example, you can run a backup of all your user accounts
# at 5 a.m every week with:
# 0 5 * * 1 tar -zcf /var/backups/home.tgz /home/
#
# For more information see the manual pages of crontab(5) and cron(8)
#
# m h  dom mon dow   command
*/5 * * * * /usr/local/bin/fail2ban-report.sh
```

# 6. Настройка интеграции с iptables

```bash
# Посмотреть текущие правила iptables
sudo iptables -L -n

# Создать новую цепь
sudo iptables -N FAIL2BAN

# Добавить правило в цепь INPUT для перенаправления трафика в цепь FAIL2BAN
sudo iptables -I INPUT -j FAIL2BAN

# Сохранить правила (чтобы они не потерялись после перезагрузки)
sudo iptables-save > /etc/iptables/rules.v4

#Далее настраиваем кастомную цепь
sudo nano /etc/fail2ban/action.d/iptables-custom.conf

#Вводим туда данные
[Definition]

actionstart = iptables -N FAIL2BAN 2>/dev/null || true
              iptables -I INPUT -j FAIL2BAN 2>/dev/null || true

actionstop = iptables -D INPUT -j FAIL2BAN 2>/dev/null || true
             iptables -F FAIL2BAN 2>/dev/null || true
             iptables -X FAIL2BAN 2>/dev/null || true

actionban = iptables -I FAIL2BAN 1 -s <ip> -j LOG --log-prefix "FAIL2BAN-BLOCK: " --log-level 4
            iptables -I FAIL2BAN 2 -s <ip> -j DROP

actionunban = iptables -D FAIL2BAN -s <ip> -j LOG 2>/dev/null || true
              iptables -D FAIL2BAN -s <ip> -j DROP 2>/dev/null || true

[Init]

#Добавляем в наш jail.local строчку в defaultrs чтобы применилось ко всем
[DEFAULT]
...
action = iptables-custom

#Проверка
sudo iptables -L -n | grep FAIL2BAN

FAIL2BAN   all  --  0.0.0.0/0            0.0.0.0/0
FAIL2BAN-PERM  all  --  0.0.0.0/0            0.0.0.0/0
FAIL2BAN   all  --  0.0.0.0/0            0.0.0.0/0
FAIL2BAN   all  --  0.0.0.0/0            0.0.0.0/0
Chain FAIL2BAN (3 references)
LOG        all  --  192.168.31.110       0.0.0.0/0            LOG flags 0 level 4 prefix "FAIL2BAN-BLOCK: "
Chain FAIL2BAN-PERM (1 references)
LOG        all  --  192.168.31.103       0.0.0.0/0            LOG flags 0 level 4 prefix "FAIL2BAN-PERM: "
LOG        all  --  192.168.31.102       0.0.0.0/0            LOG flags 0 level 4 prefix "FAIL2BAN-PERM: "

#Настраиваем логирование для обеих цепей
sudo nano /etc/rsyslog.d/fail2ban-iptables.conf

#Вводим
# Логи для обычных банов
:msg, contains, "FAIL2BAN-BLOCK" /var/log/fail2ban-iptables.log
# Логи для перманентных банов
:msg, contains, "FAIL2BAN-PERM" /var/log/fail2ban-iptables.log
& stop

#Для логирования был настроен отдельный скрипт который был включен для того чтобы ловить логи
sudo nano /usr/local/bin/fail2ban-logger.sh

#В нем вот такой конфиг 
#!/bin/bash

LOG_FILE="/var/log/fail2ban-iptables.log"

# Создаем файл если его нет
touch $LOG_FILE
chmod 644 $LOG_FILE

# Используем dmesg для мониторинга
dmesg -w | while read line; do
    if echo "$line" | grep -q "FAIL2BAN"; then
        echo "$line" >> $LOG_FILE
    fi
done

#Запускаем скрипт 
sudo nohup /usr/local/bin/fail2ban-logger.sh &

#Проверяем логи
dop2@dop2:/$ sudo fail2ban-client set sshd banip 192.168.31.102 1 

dop2@dop2:/$ sleep 3 dop2@dop2:/$ sudo tail -10 /var/log/fail2ban-iptables.log 

[28203.671845] FAIL2BAN-BLOCK: IN=enp0s3 OUT= MAC=ff:ff:ff:ff:ff:ff:d8:43:ae:c2:10:24:08:00 SRC=192.168.31.102 DST=192.168.31.255 LEN=229 TOS=0x00 PREC=0x00 TTL=128 ID=17663 PROTO=UDP SPT=138 DPT=138 LEN=209 [28922.457106] FAIL2BAN-BLOCK: IN=enp0s3 OUT= MAC=ff:ff:ff:ff:ff:ff:d8:43:ae:c2:10:24:08:00 SRC=192.168.31.102 DST=192.168.31.255 LEN=229 TOS=0x00 PREC=0x00 TTL=128 ID=17664 PROTO=UDP SPT=138 DPT=138 LEN=209 [29642.242540] FAIL2BAN-BLOCK: IN=enp0s3 OUT= MAC=ff:ff:ff:ff:ff:ff:d8:43:ae:c2:10:24:08:00 SRC=192.168.31.102 DST=192.168.31.255 LEN=229 TOS=0x00 PREC=0x00 TTL=128 ID=17665 PROTO=UDP SPT=138 DPT=138 LEN=209 [29642.242546] FAIL2BAN-BLOCK: IN=enp0s3 OUT= MAC=ff:ff:ff:ff:ff:ff:d8:43:ae:c2:10:24:08:00 SRC=192.168.31.102 DST=192.168.31.255 LEN=229 TOS=0x00 PREC=0x00 TTL=128 ID=17665 PROTO=UDP SPT=138 DPT=138 LEN=209 [29642.242550] FAIL2BAN-BLOCK: IN=enp0s3 OUT= MAC=ff:ff:ff:ff:ff:ff:d8:43:ae:c2:10:24:08:00 SRC=192.168.31.102 DST=192.168.31.255 LEN=229 TOS=0x00 PREC=0x00 TTL=128 ID=17665 PROTO=UDP SPT=138 DPT=138 LEN=209 [30363.040557] FAIL2BAN-BLOCK: IN=enp0s3 OUT= MAC=ff:ff:ff:ff:ff:ff:d8:43:ae:c2:10:24:08:00 SRC=192.168.31.102 DST=192.168.31.255 LEN=229 TOS=0x00 PREC=0x00 TTL=128 ID=17666 PROTO=UDP SPT=138 DPT=138 LEN=209 [30363.040569] FAIL2BAN-BLOCK: IN=enp0s3 OUT= MAC=ff:ff:ff:ff:ff:ff:d8:43:ae:c2:10:24:08:00 SRC=192.168.31.102 DST=192.168.31.255 LEN=229 TOS=0x00 PREC=0x00 TTL=128 ID=17666 PROTO=UDP SPT=138 DPT=138 LEN=209 [30363.040573] FAIL2BAN-BLOCK: IN=enp0s3 OUT= MAC=ff:ff:ff:ff:ff:ff:d8:43:ae:c2:10:24:08:00 SRC=192.168.31.102 DST=192.168.31.255 LEN=229 TOS=0x00 PREC=0x00 TTL=128 ID=17666 PROTO=UDP SPT=138 DPT=138 LEN=209 [31080.442214] FAIL2BAN-BLOCK: IN=enp0s3 OUT= MAC=ff:ff:ff:ff:ff:ff:d8:43:ae:c2:10:24:08:00 SRC=192.168.31.102 DST=192.168.31.255 LEN=229 TOS=0x00 PREC=0x00 TTL=128 ID=17667 PROTO=UDP SPT=138 DPT=138 LEN=209 [33958.286207] FAIL2BAN-PERM: IN=enp0s3 OUT= MAC=ff:ff:ff:ff:ff:ff:d8:43:ae:c2:10:24:08:00 SRC=192.168.31.102 DST=192.168.31.255 LEN=229 TOS=0x00 PREC=0x00 TTL=128 ID=17671 PROTO=UDP SPT=138 DPT=138 LEN=209
```
