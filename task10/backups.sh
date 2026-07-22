#!/bin/bash

#Переменные
DATE=$(date +%Y_%m_%d__%H_%M_%S)
BACK_DIR="/tmp/backups"
OLDER_GZ=$(find /tmp/backups -name "backup_*.tar.gz" -mtime +7)

#Создание папки если нет
mkdir -p $BACK_DIR

#Создаем архив с бэкапами
tar -czf /tmp/backups/backup_${DATE}.tar.gz /etc/hostname /etc/os-release

#Удаляем все что старше 7 дней
find /tmp/backups -name "backup_*.tar.gz" -mtime +7 -delete


#Какой бэкап был создан
echo "=============================================="
echo "Creating backup: backup_${DATE}.tar.gz"

#Вывод списка что будет удалено
echo "=============================================="
echo "Removing backups older than 7 days:"
echo "$OLDER_GZ"

#Вывод содержимого папки
echo "=============================================="
echo "Current backups:"
ls -lh $BACK_DIR
