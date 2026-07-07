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
