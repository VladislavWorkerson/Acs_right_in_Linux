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
