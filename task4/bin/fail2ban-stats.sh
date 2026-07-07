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
