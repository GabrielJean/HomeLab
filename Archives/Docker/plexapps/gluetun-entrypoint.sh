#!/bin/sh
set -eu

# Docker invokes the image healthcheck through the entrypoint. It must not
# regenerate credentials or the WireGuard configuration for a health probe.
if [ "${1:-}" = "healthcheck" ]; then
	exec /gluetun-entrypoint "$@"
fi

: "${PIA_USERNAME:?PIA_USERNAME must be set}"
: "${PIA_PASSWORD:?PIA_PASSWORD must be set}"
: "${PIA_REGION:?PIA_REGION must be set}"

mkdir -p /gluetun/wireguard
cd /gluetun/wireguard
/usr/local/bin/generate-pia-wireguard --region "$PIA_REGION"
unset PIA_USERNAME PIA_PASSWORD

exec /gluetun-entrypoint "$@"
