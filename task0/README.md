#ДЗ по созданию скрипта с данными

## 1. Создание легкого скрипта с данными

И так вначале у нас стоит шебанг, который говорит, через что и как запустить наш файл.

#!/bin/bash

# ===== Сбор данных =====
HOSTNAME=$(hostname) #Выодим имя хоста
UPTIME=$(uptime | awk '{print $2, $3}' | sed 's/,//') #Здесь мы выводим некоторые данные из строки uptime, используем awk для фильтрации и показа нужных столбцов 2 и 3, в конце с помощью sed убираем ,
LOAD=$(cat /proc/loadavg | awk '{print $1}') #(awk '{print $1}' /proc/loadavg)#Тут два способа вытащить нагрузку процессора в 1 минуту
RAM=$(free -h | awk '/^Mem:/{print $7}') #Вытаскиваем нужное значения ОЗУ
DISK=$(df -h / | awk 'NR==2{print $5}') #Вытаскиваем нужное количество дискового простанства
PORTS=$(ss -tuln | grep LISTEN | awk '{print $5}' | awk -F: '{print $NF}' | sort -n | uniq | xargs) #Смотрим какие порты открыты

# ===== Вывод =====
echo "================================="
echo "=== SYSTEM INFO ==="
echo "Hostname:     $HOSTNAME"
echo "Uptime:       $UPTIME"
echo "CPU load:     $LOAD (1 min avg)"
echo "RAM free:     $RAM available"
echo "Disk usage /: $DISK used"
echo "Open ports:   $PORTS"
echo "================================="


# 2. Создание более сложного скрипта для мониторинга с алертами


#!/bin/bash

# ===== Сбор данных =====
HOSTNAME=$(hostname)
UPTIME=$(uptime | awk '{print $2, $3}' | sed 's/,//')
LOAD=$(cat /proc/loadavg | awk '{print $1}') #(awk '{print $1}' /proc/loadavg)
RAM=$(free -h | awk '/^Mem:/{print $7}')
DISK=$(df -h / | awk 'NR==2{print $5}')
PORTS=$(ss -tuln | grep LISTEN | awk '{print $5}' | awk -F: '{print $NF}' | sort -n | uniq | xargs)

# ===== Вывод =====
echo "================================="
echo "=== SYSTEM INFO ==="
echo "Hostname:     $HOSTNAME"
echo "Uptime:       $UPTIME"
echo "CPU load:     $LOAD (1 min avg)"
echo "RAM free:     $RAM available"
echo "Disk usage /: $DISK used"
echo "Open ports:   $PORTS"
echo "================================="
dop2@dop2:~/LiTasks/task0$ nano README.md
dop2@dop2:~/LiTasks/task0$ cat system_file2.sh
#!/bin/bash

# ===== ANSI-цвета =====
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

# ===== Сбор данных =====
HOSTNAME=$(hostname)
UPTIME=$(uptime | awk '{print $2, $3}' | sed 's/,//')
LOAD=$(awk '{print $1}' /proc/loadavg)
RAM=$(free -h | awk '/^Mem:/{print $7}')
DISK=$(df -h / | awk 'NR==2{print $5}')
PORTS=$(ss -tuln | grep LISTEN | awk '{print $5}' | awk -F: '{print $NF}' | sort -n | uniq | xargs)

# ===== Цвет для CPU =====
if (( $(echo "$LOAD < 1.0" | bc -l) )); then
    LOAD_COLOR="${GREEN}"
elif (( $(echo "$LOAD > 2.0" | bc -l) )); then
    LOAD_COLOR="${RED}"
else
    LOAD_COLOR="${YELLOW}"
fi

# ===== Цвет для RAM =====
RAM_VAL=$(echo "$RAM" | sed 's/[^0-9.]//g')
RAM_UNIT=$(echo "$RAM" | sed 's/[0-9.]//g')
if [[ "$RAM_UNIT" == "Gi" ]] && (( $(echo "$RAM_VAL < 1.0" | bc -l) )); then
    RAM_COLOR="${RED}"
elif [[ "$RAM_UNIT" == "Mi" ]]; then
    RAM_COLOR="${RED}"
elif [[ "$RAM_UNIT" == "Gi" ]] && (( $(echo "$RAM_VAL < 4.0" | bc -l) )); then
    RAM_COLOR="${YELLOW}"
else
    RAM_COLOR="${GREEN}"
fi

# ===== Цвет для диска =====
DISK_PCT=$(echo "$DISK" | sed 's/%//')
if (( $(echo "$DISK_PCT > 80" | bc -l) )); then
    DISK_COLOR="${RED}"
elif (( $(echo "$DISK_PCT > 60" | bc -l) )); then
    DISK_COLOR="${YELLOW}"
else
    DISK_COLOR="${GREEN}"
fi

# ===== Вывод =====
echo "================================="
echo "=== SYSTEM INFO ==="
echo -e "Hostname:     ${GREEN}${HOSTNAME}${NC}"
echo -e "Uptime:       ${UPTIME}"
echo -e "CPU load:     ${LOAD_COLOR}${LOAD}${NC} (1 min avg)"
echo -e "RAM free:     ${RAM_COLOR}${RAM}${NC} available"
echo -e "Disk usage /: ${DISK_COLOR}${DISK}${NC} used"
echo -e "Open ports:   ${PORTS}"

# ===== Проверка порогов =====
ALERTS=""
if (( $(echo "$LOAD > 1.0" | bc -l) )); then
    ALERTS+="⚠  CPU load is high (${LOAD})\n"
fi
if [[ -n "$RAM_COLOR" ]] && [[ "$RAM_COLOR" == "${RED}" ]]; then
    ALERTS+="⚠  Low memory (${RAM} available)\n"
fi
if (( $(echo "$DISK_PCT > 80" | bc -l) )); then
    ALERTS+="⚠  Disk space is running out (${DISK} used)\n"
fi
IOWAIT=$(vmstat 1 2 | tail -1 | awk '{print $16}')
if (( $(echo "$IOWAIT > 10" | bc -l) )); then
    ALERTS+="⚠  High I/O wait (${IOWAIT}%)\n"
fi

if [[ -n "$ALERTS" ]]; then
    echo -e "\n=== ALERTS ==="
    echo -e "$ALERTS"
fi

echo "================================="
