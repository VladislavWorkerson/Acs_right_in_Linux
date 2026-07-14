
# Задание. Скрипт проверки портов

**Задание**

Напиши скрипт `check_ports.sh`, который:

1. Содержит список хостов и портов для проверки (захардкожено в скрипте)
2. Проверяет каждый хост:порт с таймаутом 2 секунды
3. Выводит результат: `OK` или `FAIL` для каждого

**Список для проверки:**
```
google.com:443
google.com:80
localhost:22
localhost:9999
```

## 1. Проверяем, установлен ли `nc`

На сервере выполни:
```bash
#Спрашиваем у системы про nc
which nc

#Предполагаемый вывод:
/usr/bin/nc

#Если nc нет его можно установить
sudo apt update
sudo apt install -y netcat-openbsd
```

---
## 2. Сначала вручную проверим команды

Выполни:
```bash
#Проверка порта вручную
nc -zv -w 2 google.com 443

#Вывод
dop2@dop2:~$ nc -zv -w 2 google.com 443
Connection to google.com (209.85.233.138) 443 port [tcp/https] succeeded!

#Затем проверяем вывод, если 0 знавчит все хорошо, если все кроме 0 значит ошибка
dop2@dop2:~$ echo $?
0

#Проверяем любой порт для проверки. Вывод должен быть не 0
nc -zv -w 2 localhost 9999
echo $?

#Вывод
dop2@dop2:~$ nc -zv -w 2 localhost 9999
nc: connect to localhost (::1) port 9999 (tcp) failed: Connection refused
nc: connect to localhost (127.0.0.1) port 9999 (tcp) failed: Connection refused
dop2@dop2:~$ echo $?
1
```

Разбор команды:
```bash
nc -zv -w 2 <host> <port>
nc -zv -w 2 google.com 443

nc # netcat
-z # только проверить порт, не отправлять данные
-v # verbose, показать подробный вывод
-w 2 # ждать максимум 2 секунды
google.com # хост
443 # порт HTTPS
```

---
## 3. Создаём скрипт

Создаем наш скрипт:
```bash
Создаем скрипт
nano ~/LiTasks/task6/check_ports.sh

#Вставляем все что ниже
#!/usr/bin/env bash

TARGETS="google.com:443 google.com:80 localhost:22 localhost:2222 localhost:9999"

for target in $TARGETS; do
    HOST=$(echo "$target" | cut -d: -f1)
    PORT=$(echo "$target" | cut -d: -f2)

    if nc -z -w 2 "$HOST" "$PORT" > /dev/null 2>&1; then
        echo "$target - OK"
    else
        echo "$target - FAIL"
    fi
done

#Делаем скрипт исполняемым
chmod +x ~/LiTasks/task6/check_ports.sh

#Проверяем права скрипта
ls -l check_ports.sh
#Вывод
dop2@dop2:~/LiTasks/task6$ ls -l check_ports.sh
-rwxrwxr-x 1 dop2 dop2 337 Jul 14 11:08 check_ports.sh #права верные и слегка полные потому что маска у нас 0002

```

---
### 3.1 Разбор скрипта

```bash
#Это shebang. Он говорит системе запускать файл через Bash.
#!/usr/bin/env bash

#Это список целей для проверки. Каждая цель записана в формате host:port 
TARGETS="google.com:443 google.com:80 localhost:22 localhost:2222 localhost:9999"

#Это цикл. Он берёт элементы списка по одному. Сначала target=google.com:443, потом target=google.com:80, далее target=google.com:80 и так далее.
for target in $TARGETS; do

#Берём из `google.com:443` первую часть до `:`. Получится google.com
HOST=$(echo "$target" | cut -d: -f1)

#Разбор
$() # Конструкция благодаря которой внутри выполняется команда
echo "$target" # вывести строку target
| # передать вывод дальше
cut # вырезать часть строки
-d: # разделитель двоеточие
-f1 # взять первое поле

#Берём вторую часть после `:`. Из google.com:443, берем 443
PORT=$(echo "$target" | cut -d: -f2)

#Данная команда проверяет TCP порт. Данная конструкция > /dev/null 2>&1 пряет ошибки
if nc -z -w 2 "$HOST" "$PORT" > /dev/null 2>&1; then
```

Далее смотри если 0, то:
```bash
echo "$target - OK"
```

Если код не `0`, значит порт закрыт или недоступен, то:
```bash
echo "$target - FAIL"
```

## 4 Запуск нашего скрипта

```bash
dop2@dop2:~/LiTasks/task6$ ./check_ports.sh
google.com:443 - OK
google.com:80 - OK
localhost:22 - FAIL
localhost:2222 - OK
localhost:9999 - FAIL
dop2@dop2:~/LiTasks/task6$ cat check_ports.sh && echo "---" && ./check_ports.sh
#!/usr/bin/env bash

TARGETS="google.com:443 google.com:80 localhost:22 localhost:2222 localhost:9999"

for target in $TARGETS; do
    HOST=$(echo "$target" | cut -d: -f1)
    PORT=$(echo "$target" | cut -d: -f2)

    if nc -z -w 2 "$HOST" "$PORT" > /dev/null 2>&1; then
        echo "$target - OK"
    else
        echo "$target - FAIL"
    fi
done
---
google.com:443 - OK
google.com:80 - OK
localhost:22 - FAIL
localhost:2222 - OK
localhost:9999 - FAIL
```

---
## 5.  Дополнительное задание

```bash
dop2@dop2:~/LiTasks/task6/task6.1$ echo "script" && cat check_ports.sh && echo "---" && echo "targets.txt" && cat targets.txt && echo "---" && echo "Result" && ./check_ports.sh
script
#!/usr/bin/env bash

TARGET_FILE="targets.txt"

while IFS= read -r target; do
    HOST=$(echo "$target" | cut -d: -f1)
    PORT=$(echo "$target" | cut -d: -f2)

    if nc -z -w 2 "$HOST" "$PORT" > /dev/null 2>&1; then
        echo "$target - OK"
    else
        echo "$target - FAIL"
    fi
done < "$TARGET_FILE"
---
targets.txt
google.com:443
google.com:80
localhost:22
localhost:2222
localhost:9999
---
Result
google.com:443 - OK
google.com:80 - OK
localhost:22 - FAIL
localhost:2222 - OK
localhost:9999 - FAIL
```
