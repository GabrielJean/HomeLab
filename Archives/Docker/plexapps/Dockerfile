FROM qmcgaw/gluetun:v3.41.1

RUN apk add --no-cache bash curl jq wireguard-tools coreutils

COPY gen_config.sh /usr/local/bin/generate-pia-wireguard
COPY gluetun-entrypoint.sh /usr/local/bin/gluetun-entrypoint

RUN chmod 0755 /usr/local/bin/generate-pia-wireguard /usr/local/bin/gluetun-entrypoint

ENTRYPOINT ["/usr/local/bin/gluetun-entrypoint"]
