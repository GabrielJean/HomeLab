#!/usr/bin/env bash

# Generate a PIA WireGuard client configuration without changing host networking
# or retaining credentials, tokens, server data, or certificates.

SERVER_LIST_URL="https://serverlist.piaservers.net/vpninfo/servers/v6"
PIA_CERT_URL="https://raw.githubusercontent.com/pia-foss/desktop/master/daemon/res/ca/rsa_4096.crt"

usage() {
	cat <<EOF
Usage: $(basename "$0") [-l] [-r REGION_ID]

Generates ./wg0.conf in the current directory.

Options:
  -l, --list-regions       List available PIA WireGuard regions and exit.
  -r, --region REGION_ID   Generate a configuration for this PIA region.
  -h, --help               Show this help text.
EOF
}

require_command() {
	if ! command -v "$1" >/dev/null 2>&1
	then
		echo "Required command not found: $1" >&2
		exit 1
	fi
}

REGION_ID="."
LIST_REGIONS=0

while [ "$#" -gt 0 ]
do
	case "$1" in
		-l|--list-regions)
			LIST_REGIONS=1
			shift
			;;
		-r|--region)
			if [ -z "${2:-}" ] || [[ "$2" == -* ]]
			then
				echo "The --region option requires a region ID" >&2
				exit 1
			fi
			REGION_ID="$2"
			shift 2
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			echo "Unrecognized option: $1" >&2
			usage >&2
			exit 1
			;;
	esac
done

require_command curl
require_command jq

if ! SERVER_LIST="$(curl --fail --silent --show-error --max-time 15 "$SERVER_LIST_URL")"
then
	echo "Unable to retrieve the PIA server list" >&2
	exit 1
fi

# PIA appends a signature after the JSON document; only its first line is JSON.
SERVER_DATA="$(head -n1 <<< "$SERVER_LIST")"
if ! jq -e '.regions | type == "array"' >/dev/null <<< "$SERVER_DATA"
then
	echo "PIA returned an invalid server list" >&2
	exit 1
fi

if [ "$LIST_REGIONS" -eq 1 ]
then
	echo -e "Region ID\tRegion\tPort forwarding\tGeolocated"
	jq -r '.regions[] | select((.servers.wg | length) > 0) | [.id, .name, (if .port_forward then "yes" else "no" end), (if .geo then "yes" else "no" end)] | @tsv' <<< "$SERVER_DATA"
	exit 0
fi

require_command wg
require_command shuf

if [ "$REGION_ID" = "." ]
then
	REGION="$(jq -c '.regions[] | select((.servers.wg | length) > 0)' <<< "$SERVER_DATA" | shuf -n1)"
else
	REGION="$(jq -c --arg region "$REGION_ID" '.regions[] | select(.id == $region and (.servers.wg | length) > 0)' <<< "$SERVER_DATA")"
fi

if [ -z "$REGION" ]
then
	echo "Region '$REGION_ID' was not found. Run $(basename "$0") --list-regions to see valid IDs." >&2
	exit 1
fi

REGION_NAME="$(jq -r '.name' <<< "$REGION")"
WG_DNS="$(jq -r '.dns' <<< "$REGION")"
SELECTED_SERVER="$(jq -c '.servers.wg[]' <<< "$REGION" | shuf -n1)"
WG_HOST="$(jq -r '.ip' <<< "$SELECTED_SERVER")"
WG_CN="$(jq -r '.cn' <<< "$SELECTED_SERVER")"
WG_PORT="$(jq -r '.groups.wg[0].ports[]' <<< "$SERVER_DATA" | shuf -n1)"

if [ -z "$WG_HOST" ] || [ -z "$WG_CN" ] || [ -z "$WG_PORT" ]
then
	echo "The selected PIA region has incomplete WireGuard data" >&2
	exit 1
fi

umask 077
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/pia-wg.XXXXXX")" || {
	echo "Unable to create temporary working directory" >&2
	exit 1
}
trap 'rm -rf -- "$WORKDIR"' EXIT

if ! curl --fail --silent --show-error --max-time 15 "$PIA_CERT_URL" -o "$WORKDIR/pia-rsa.crt"
then
	echo "Unable to retrieve the PIA certificate" >&2
	exit 1
fi

read -r -p "PIA username: " PIA_USERNAME
if [ -z "$PIA_USERNAME" ]
then
	echo "A PIA username is required" >&2
	exit 1
fi

read -r -s -p "PIA password: " PIA_PASSWORD
echo
if [ -z "$PIA_PASSWORD" ]
then
	echo "A PIA password is required" >&2
	exit 1
fi

AUTH_BODY="$(jq -nc --arg username "$PIA_USERNAME" --arg password "$PIA_PASSWORD" '{username: $username, password: $password}')"
TOKEN="$(curl --silent --show-error --max-time 15 --request POST --header 'Content-Type: application/json' --data "$AUTH_BODY" 'https://www.privateinternetaccess.com/api/client/v2/token' | jq -r '.token // empty')"
unset PIA_PASSWORD AUTH_BODY

if [ -z "$TOKEN" ]
then
	echo "PIA authentication failed" >&2
	exit 1
fi

CLIENT_PRIVATE_KEY="$(wg genkey)"
CLIENT_PUBLIC_KEY="$(wg pubkey <<< "$CLIENT_PRIVATE_KEY")"

register_key() {
	curl --silent --show-error --max-time 10 --get \
		--data-urlencode "pubkey=$CLIENT_PUBLIC_KEY" \
		--data-urlencode "pt=$TOKEN" \
		--cacert "$WORKDIR/pia-rsa.crt" \
		--resolve "$1:$WG_PORT:$WG_HOST" \
		"https://$1:$WG_PORT/addKey"
}

echo "Registering key with $REGION_NAME ($WG_HOST)"
REMOTE_INFO="$(register_key "$WG_CN")" || REMOTE_INFO="$(register_key "$WG_DNS")"
unset TOKEN

if [ "$(jq -r '.status // empty' <<< "$REMOTE_INFO")" != "OK" ]
then
	echo "PIA rejected the WireGuard key registration" >&2
	exit 1
fi

PEER_IP="$(jq -r '.peer_ip // empty' <<< "$REMOTE_INFO")"
SERVER_PUBLIC_KEY="$(jq -r '.server_key // empty' <<< "$REMOTE_INFO")"
SERVER_IP="$(jq -r '.server_ip // empty' <<< "$REMOTE_INFO")"
SERVER_PORT="$(jq -r '.server_port // empty' <<< "$REMOTE_INFO")"
DNS_SERVERS="$(jq -r '[.dns_servers[0:2][]] | join(",")' <<< "$REMOTE_INFO")"

if [ -z "$PEER_IP" ] || [ -z "$SERVER_PUBLIC_KEY" ] || [ -z "$SERVER_IP" ] || [ -z "$SERVER_PORT" ] || [ -z "$DNS_SERVERS" ]
then
	echo "PIA returned incomplete WireGuard configuration data" >&2
	exit 1
fi

WGCONF="$(pwd -P)/wg0.conf"
cat > "$WGCONF" <<EOF
[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address = $PEER_IP
DNS = $DNS_SERVERS

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = $SERVER_IP:$SERVER_PORT
EOF

echo "Generated $WGCONF for $REGION_NAME"

if command -v qrencode >/dev/null 2>&1
then
	qrencode -t ansiutf8 < "$WGCONF"
fi
