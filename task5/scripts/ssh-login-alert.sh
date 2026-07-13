#!/usr/bin/env bash

LOG_FILE="/var/log/ssh-login-alerts.log"

{
  echo "========================================"
  echo "SSH LOGIN ALERT"
  echo "Time: $(date --iso-8601=seconds)"
  echo "User: ${PAM_USER:-unknown}"
  echo "Remote host: ${PAM_RHOST:-unknown}"
  echo "Service: ${PAM_SERVICE:-unknown}"
  echo "TTY: ${PAM_TTY:-unknown}"
  echo "Server: $(hostname -f 2>/dev/null || hostname)"
  echo "========================================"
  echo
} >> "$LOG_FILE"

exit 0
