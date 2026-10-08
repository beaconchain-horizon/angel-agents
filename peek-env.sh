#!/usr/bin/env bash
# نمایش امن env — فقط نام‌ها، نه مقادیر
while IFS='=' read -r key val; do
  [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
  if [ -n "$val" ]; then
    echo "$key=<set, ${#val} chars>"
  else
    echo "$key=<empty>"
  fi
done < .env.local
