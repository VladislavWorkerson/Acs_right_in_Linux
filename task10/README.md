# Задание

Напиши скрипт `backup.sh`, который:

1. Создаёт директорию `/tmp/backups` (если не существует)
2. Архивирует `/etc/hostname` и `/etc/os-release` в файл `backup_YYYY-MM-DD_HHMMSS.tar.gz`
3. Кладёт архив в `/tmp/backups/`
4. Удаляет из `/tmp/backups/` архивы старше 7 дней
5. Выводит список оставшихся архивов

# Ход выполнения:

Создаем скрипт который будет делать новые бэкапы и удалять старые. Смотрим на коды ниже:

```bash
#Создаем файл для скрипта backups.sh
sudo touch /usr/local/bin/backups.sh

#Даем права на запуск
sudo chmod +x /usr/local/bin/backups.sh

#Редактируем файл
sudo nano /usr/local/bin/backups.sh

#Вставляем код:
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
```

# Проверка с добавлением файла и удалением

```bash
dop2@dop2:/$ ls -l /tmp/backups/
ls: cannot access '/tmp/backups/': No such file or directory

dop2@dop2:/$ bash /usr/local/bin/backups.sh
find: ‘/tmp/backups’: No such file or directory
tar: Removing leading / from member names
tar: Removing leading / from hard link targets

==============================================
Creating backup: backup_2026_07_22__14_20_41.tar.gz
==============================================
Removing backups older than 7 days:

==============================================
Current backups:
total 4.0K
-rw-rw-r-- 1 dop2 dop2 177 Jul 22 14:20 backup_2026_07_22__14_20_41.tar.gz


dop2@dop2:/$ touch -d "10 days ago" /tmp/backups/backup_2025-01-12_100000.tar.gz

dop2@dop2:/$ bash /usr/local/bin/backups.sh
tar: Removing leading / from member names
tar: Removing leading / from hard link targets
==============================================
Creating backup: backup_2026_07_22__14_21_00.tar.gz
==============================================
Removing backups older than 7 days:
/tmp/backups/backup_2025-01-12_100000.tar.gz
==============================================
Current backups:
total 8.0K
-rw-rw-r-- 1 dop2 dop2 177 Jul 22 14:20 backup_2026_07_22__14_20_41.tar.gz
-rw-rw-r-- 1 dop2 dop2 177 Jul 22 14:21 backup_2026_07_22__14_21_00.tar.gz
```
