#!/bin/bash

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
