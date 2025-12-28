#!/bin/sh
# Run on wall-clock quarter-hours (e.g., 15:00, 15:15, 15:30, 15:45).
trap "exit 0" INT TERM

QUARTER=900 # seconds

sleep_until_next_slot() {
  now=$(date +%s)
  next=$(( (now / QUARTER + 1) * QUARTER ))
  delay=$(( next - now ))
  [ "$delay" -gt 0 ] && sleep "$delay"
}

# Align first run to the next quarter-hour.
sleep_until_next_slot

while true; do
  python gmap.py
  status=$?
  if [ "$status" -ne 0 ]; then
    echo "gmap run failed with status $status; retrying in 60s" >&2
    sleep 60
    continue
  fi

  sleep_until_next_slot
done
