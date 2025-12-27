#!/bin/sh
# Simple loop to run the scraper every 15 minutes.
trap "exit 0" INT TERM

while true; do
  python gmap.py
  status=$?
  if [ "$status" -ne 0 ]; then
    echo "gmap run failed with status $status; retrying in 60s" >&2
    sleep 60
  else
    sleep 900
  fi
done
