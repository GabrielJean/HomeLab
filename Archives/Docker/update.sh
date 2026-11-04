#!/bin/bash

git pull

for d in */ ; do
  if [[ "$d" != "adguardhome/" && "$d" != "plex/" ]]; then
    (cd "$d" && docker compose pull && docker compose up --build -d)
  fi
done