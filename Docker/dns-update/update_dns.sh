#!/bin/bash

set -euo pipefail

# Logging helper with timestamps
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Required env:
# - AZURE_APP_ID, AZURE_TENANT_ID, AZURE_SECRET
# - RESOURCE_GROUP, DNS_ZONE_NAME
# - MAIN_RECORD_NAME: host label for A record (e.g., "gaming")
# - CNAME_NAMES: comma-separated list of CNAME labels (e.g., "satisfactory,astroneer,zomboid")

# Validate required environment variables
missing_vars=()
for var in AZURE_APP_ID AZURE_TENANT_ID AZURE_SECRET RESOURCE_GROUP DNS_ZONE_NAME MAIN_RECORD_NAME; do
  if [[ -z "${!var:-}" ]]; then
    missing_vars+=("$var")
  fi
done

if (( ${#missing_vars[@]} > 0 )); then
  log "ERROR: The following required environment variables are missing:"
  for var in "${missing_vars[@]}"; do
    log "  - $var"
  done
  exit 1
fi

log "INFO: DNS updater started. Main record: MAIN_RECORD_NAME=$MAIN_RECORD_NAME, CNAMEs: CNAME_NAMES=${CNAME_NAMES:-none}"

FULL_MAIN_NAME="${MAIN_RECORD_NAME}.${DNS_ZONE_NAME}"

while true; do
  CURRENT_IP=$(curl -s http://ifconfig.me 2>&1)
  if [[ -z "$CURRENT_IP" ]]; then
    log "WARN: Failed to retrieve public IP. Retrying in 10 minutes..."
    sleep 600
    continue
  fi

  log "DEBUG: Current public IP is $CURRENT_IP"

  # Authenticate with Azure CLI using the service principal
  if ! az login --service-principal -u "$AZURE_APP_ID" -p "$AZURE_SECRET" --tenant "$AZURE_TENANT_ID" >/dev/null 2>&1; then
    log "ERROR: Azure CLI login failed. Retrying in 10 minutes..."
    sleep 600
    continue
  fi

  log "DEBUG: Azure CLI authentication successful"

  # Ensure the A record-set exists
  if ! az network dns record-set a show \
      --resource-group "$RESOURCE_GROUP" \
      --zone-name "$DNS_ZONE_NAME" \
      --name "$MAIN_RECORD_NAME" >/dev/null 2>&1; then
    log "INFO: Creating A record-set for $MAIN_RECORD_NAME"
    az network dns record-set a create \
      --resource-group "$RESOURCE_GROUP" \
      --zone-name "$DNS_ZONE_NAME" \
      --name "$MAIN_RECORD_NAME" \
      --ttl 300 >/dev/null
  fi

  # Compare and update A record
  EXISTING_IP=$(az network dns record-set a show \
    --resource-group "$RESOURCE_GROUP" \
    --zone-name "$DNS_ZONE_NAME" \
    --name "$MAIN_RECORD_NAME" \
    --query "ARecords[0].ipv4Address" -o tsv 2>/dev/null || true)

  if [[ "$CURRENT_IP" == "$EXISTING_IP" && -n "$EXISTING_IP" ]]; then
    log "INFO: A record ${FULL_MAIN_NAME} already set to $CURRENT_IP"
  else
    # Clear existing A records then add the current IP to avoid array index issues
    if [[ -n "$EXISTING_IP" ]]; then
      log "INFO: Removing old A record IP $EXISTING_IP"
      az network dns record-set a remove-record \
        --resource-group "$RESOURCE_GROUP" \
        --zone-name "$DNS_ZONE_NAME" \
        --record-set-name "$MAIN_RECORD_NAME" \
        --ipv4-address "$EXISTING_IP" >/dev/null 2>&1 || true
    fi

    log "INFO: Adding new A record IP $CURRENT_IP for ${FULL_MAIN_NAME}"
    az network dns record-set a add-record \
      --resource-group "$RESOURCE_GROUP" \
      --zone-name "$DNS_ZONE_NAME" \
      --record-set-name "$MAIN_RECORD_NAME" \
      --ipv4-address "$CURRENT_IP" >/dev/null

    log "INFO: Updated A record ${FULL_MAIN_NAME} to $CURRENT_IP"
  fi

  # Manage CNAMEs pointing to the main record
  if [[ -n "${CNAME_NAMES:-}" ]]; then
    log "DEBUG: Processing CNAMEs: $CNAME_NAMES"
    IFS=',' read -r -a cname_array <<< "$CNAME_NAMES"
    for cname in "${cname_array[@]}"; do
      cname_trimmed="$(echo "$cname" | xargs)"
      [[ -z "$cname_trimmed" ]] && continue

      # Ensure CNAME record-set exists
      if ! az network dns record-set cname show \
          --resource-group "$RESOURCE_GROUP" \
          --zone-name "$DNS_ZONE_NAME" \
          --name "$cname_trimmed" >/dev/null 2>&1; then
        log "INFO: Creating CNAME record-set for $cname_trimmed"
        az network dns record-set cname create \
          --resource-group "$RESOURCE_GROUP" \
          --zone-name "$DNS_ZONE_NAME" \
          --name "$cname_trimmed" \
          --ttl 300 >/dev/null
      fi

      # Set/overwrite the CNAME target to the full main record
      log "INFO: Ensuring CNAME ${cname_trimmed}.${DNS_ZONE_NAME} -> ${FULL_MAIN_NAME}"
      az network dns record-set cname set-record \
        --resource-group "$RESOURCE_GROUP" \
        --zone-name "$DNS_ZONE_NAME" \
        --record-set-name "$cname_trimmed" \
        --cname "$FULL_MAIN_NAME" >/dev/null

      log "DEBUG: CNAME ${cname_trimmed}.${DNS_ZONE_NAME} verified -> ${FULL_MAIN_NAME}"
    done
  else
    log "DEBUG: No CNAMEs to manage (CNAME_NAMES is empty or not set)"
  fi

  log "INFO: DNS sync completed. Sleeping for 10 minutes..."
  sleep 600
done