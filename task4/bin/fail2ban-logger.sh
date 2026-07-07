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
