#!/usr/bin/env bash
# sagar_simple_small.sh - simple menu-driven system health + email report (ssmtp)
# Usage:
#   ./sagar_simple_small.sh           # interactive
#   DEBUG=1 ./sagar_simple_small.sh   # debug traces
#   ./sagar_simple_small.sh --report  # build report and send (non-interactive)
#
# Configure EMAIL below or export EMAIL env before running

EMAIL="${EMAIL:-rout.kmr@gmail.com}"     # recipient (override via env)
REPORT="/tmp/sagar_simple_report.txt"
DEBUG="${DEBUG:-0}"

# simple debug log
dbg() { [ "$DEBUG" -eq 1 ] && echo "[DEBUG] $*"; }

# build report (overwrites REPORT)
build_report() {
  {
    echo "System Health Report - $(hostname -f 2>/dev/null || hostname)"
    echo "Generated: $(date -Iseconds)"
    echo
    echo "=== Disk ==="
    df -hP || true
    echo
    echo "=== Memory ==="
    if command -v free >/dev/null 2>&1; then free -h; else awk '/MemTotal/ {print; exit}' /proc/meminfo; fi
    echo
    echo "=== CPU / Load ==="
    if [ -f /proc/loadavg ]; then awk '{print "Load avg:", $1,$2,$3}' /proc/loadavg; else uptime; fi
    echo
    echo "=== Top CPU processes ==="
    ps aux --sort=-%cpu | head -n 6 || true
    echo
    echo "=== Top MEM processes ==="
    ps aux --sort=-%mem | head -n 6 || true
  } > "$REPORT"
  dbg "Report written to $REPORT"
}

# send report via ssmtp (assumes ssmtp is configured)
send_report() {
  if [ ! -f "$REPORT" ]; then
    echo "Report not found, building..."
    build_report
  fi

  # Simple email headers and body
  {
    echo "Subject: System Health Report - $(hostname)"
    echo "From: $EMAIL"
    echo "To: $EMAIL"
    echo
    cat "$REPORT"
  } | ssmtp -v "$EMAIL"
  local rc=$?
  if [ $rc -eq 0 ]; then
    echo "Email sent to $EMAIL"
  else
    echo "Failed to send email (ssmtp exit code $rc)"
  fi
  return $rc
}

# small checks used by menu options
check_disk() { df -hP | sed -n '1,8p'; }
check_services() {
  if command -v systemctl >/dev/null 2>&1; then
    systemctl list-units --type=service --state=running --no-legend --no-pager | awk '{print $1, $4}' | head -n 12
  else
    ps aux --sort=-%cpu | head -n 10
  fi
}
check_memory() { free -h || awk '/MemTotal/ {print "MemTotal present but free not found"}' /proc/meminfo; }
check_cpu() { uptime; echo; ps aux --sort=-%cpu | head -n 6; }

# interactive menu
menu() {
  while true; do
    cat <<EOF

=== Sagar Simple Health ===
1) Check Disk Usage
2) Monitor Running Services
3) Assess Memory Usage
4) Evaluate CPU Usage
5) Build & Send Report now
6) Exit
EOF
    read -rp "Choose [1-6]: " choice
    case "$choice" in
      1) check_disk ;;
      2) check_services ;;
      3) check_memory ;;
      4) check_cpu ;;
      5) build_report && send_report ;;
      6) echo "Bye"; exit 0 ;;
      *) echo "Invalid choice" ;;
    esac
    echo
    read -rp "Press Enter to continue..." _
  done
}

# CLI: non-interactive report mode
if [ "${1:-}" = "--report" ]; then
  [ "$DEBUG" -eq 1 ] && set -x
  build_report
  send_report
  exit $?
fi

# default: interactive
[ "$DEBUG" -eq 1 ] && set -x
menu

