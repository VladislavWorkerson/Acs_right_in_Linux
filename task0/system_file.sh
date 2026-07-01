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
