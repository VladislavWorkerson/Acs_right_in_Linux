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


# Записать в CSV (>> означает дописать в конец файла)
echo "$TIMESTAMP,sshd,$CB_SSH,$TB_SSH" >> /var/log/fail2ban-metrics.csv
echo "$TIMESTAMP,nginx,$CB_NGINX,$TB_NGINX" >> /var/log/fail2ban-metrics.csv
echo "$TIMESTAMP,postgresql,$CB_PGSQL,$TB_PGSQL" >> /var/log/fail2ban-metrics.csv


# Создать JSON вручную через echo
cat > /var/log/fail2ban-metrics.json << EOF
{
  "timestamp": "$TIMESTAMP",
  "jails": {
    "sshd": {"currently_banned": $CB_SSH, "total_banned": $TB_SSH},
    "nginx-auth": {"currently_banned": $CB_NGINX, "total_banned": $TB_NGINX},
    "postgresql": {"currently_banned": $CB_PGSQL, "total_banned": $TB_PGSQL}
  },
  "totals": {
    "currently_banned": $TOTAL_CB,
    "total_banned": $TOTAL_TB
  }
}
EOF
