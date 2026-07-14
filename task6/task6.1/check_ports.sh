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
