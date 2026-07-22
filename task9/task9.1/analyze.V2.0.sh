#!/bin/bash

if [ -z "$1" ]; then
    echo "Ошибка: укажите путь к директории"
    echo "Пример: ./analyze.V2.0.sh /etc"
    exit 1
fi

if [ ! -d "$1" ]; then
    echo "Ошибка: $1 не является директорией"
    exit 1
fi

files=0
dirs=0

for item in "$1"/*; do
    if [ -d "$item" ]; then
        ((dirs++))
    elif [ -f "$item" ]; then
        ((files++))
    fi
done

echo "Files: $files"
echo "Directories: $dirs"
