#!/bin/sh
set -e

./main.sh
/usr/sbin/crond -f -l 8
