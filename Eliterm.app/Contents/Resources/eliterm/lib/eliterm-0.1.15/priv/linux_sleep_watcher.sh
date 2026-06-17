#!/bin/bash
# Simple sleep watcher for Linux using dbus-monitor

echo "READY"

# Monitor for PrepareForSleep signal
dbus-monitor --system "type='signal',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'" | while read -r line; do
  if echo "$line" | grep -q "boolean true"; then
    echo "SLEEP_DETECTED"
    # Wait for Elixir to reply MIGRATION_DONE or timeout after 25s
    if read -t 25 ACK; then
      if [ "$ACK" = "MIGRATION_DONE" ]; then
        echo "ACK_SLEEP"
      else
        echo "TIMEOUT_SLEEP"
      fi
    else
      echo "TIMEOUT_SLEEP"
    fi
  fi
done
