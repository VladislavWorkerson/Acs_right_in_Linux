# Задание:

Напиши скрипт `analyze.sh`, который:

1. Принимает путь к директории как аргумент (например, `./analyze.sh /etc`)
2. Перебирает всё содержимое этой директории
3. Для каждого элемента определяет: это файл или директория
4. Выводит статистику: сколько файлов, сколько директорий

# Ход выполнения:

```bash
#Создаем папку в которой будет лежать скрипт
mkdir -p ~/LiTask/task9

#Создаем первый скрипт без доп. задач
touch analyze.V1.0.sh

#Даем права на запуск данного файла
chmod +x analyze.V1.0.sh

#Заходим внутрь скрипта
nano analyze.V1.0.sh

#Вставляем следующие строчки:
#!/bin/bash #Шебанг 

files=0 #Обнуляем счетчик файлов
dirs=0 #Обнуляем счетчик папок

for item in "$1"/*; do #Начало цикла. Берем данные первого аргумента
    if [ -d "$item" ]; then #Смотрим файл это или нет
        ((dirs++)) #Добавляем если да
    elif [ -f "$item" ]; then #Смотрим папка это или нет
        ((files++)) #Добавляем если да
    fi
done

echo "Files: $files"
echo "Directories: $dirs"

#Вывод:
dop2@dop2:~/LiTasks/task9$ ./analyze.V1.0.sh /etc
Files: 92
Directories: 122
```

# Дополнительное задание:

```bash

#Создаем папку в которой будет лежать скрипт
mkdir -p ~/LiTask/task9.1

#Создаем первый скрипт без доп. задач
touch analyze.V2.0.sh

#Даем права на запуск данного файла
chmod +x analyze.V2.0.sh

#Заходим внутрь скрипта
nano analyze.V2.0.sh

#Вставляем следующие строчки:
#!/bin/bash #Шебанг 

files=0 #Обнуляем счетчик файлов
dirs=0 #Обнуляем счетчик папок

for item in "$1"/*; do #Начало цикла. Берем данные первого аргумента
    if [ -d "$item" ]; then #Смотрим файл это или нет
        ((dirs++)) #Добавляем если да
    elif [ -f "$item" ]; then #Смотрим папка это или нет
        ((files++)) #Добавляем если да
    fi
done

echo "Files: $files"
echo "Directories: $dirs"

#Вывод:
dop2@dop2:~/LiTasks/task9$ bash task9.1/analyze.V2.0.sh
Ошибка: укажите путь к директории
Пример: ./analyze.V2.0.sh /etc

dop2@dop2:~/LiTasks/task9$ bash task9.1/analyze.V2.0.sh /etc
Files: 92
Directories: 122

dop2@dop2:~/LiTasks/task9$ bash task9.1/analyze.V2.0.sh /nohup.out
Ошибка: /nohup.out не является директорией
```
