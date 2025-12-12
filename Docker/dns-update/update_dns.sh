#!/bin/bash

set -euo pipefail

# Required env:
# - AZURE_APP_ID, AZURE_TENANT_ID, AZURE_SECRET
# - RESOURCE_GROUP, DNS_ZONE_NAME
# - MAIN_RECORD_NAME: host label for A record (e.g., "gaming")
# - CNAME_NAMES: comma-separated list of CNAME labels (e.g., "satisfactory,astroneer,zomboid")

if [[ -z "${AZURE_APP_ID:-}" || -z "${AZURE_TENANT_ID:-}" || -z "${AZURE_SECRET:-}" || -z "${RESOURCE_GROUP:-}" || -z "${DNS_ZONE_NAME:-}" || -z "${MAIN_RECORD_NAME:-}" ]]; then
  echo "One or more required environment variables are missing. Exiting."
  exit 1
fi

FULL_MAIN_NAME="${MAIN_RECORD_NAME}.${DNS_ZONE_NAME}"

while true; do
  CURRENT_IP=$(curl -s http://ifconfig.me)
  if [[ -z "$CURRENT_IP" ]]; then
    echo "Failed to retrieve public IP. Retrying in 10 minutes..."
    sleep 600
    continue
  fi

  # Authenticate with Azure CLI using the service principal
  if ! az login --service-principal -u "$AZURE_APP_ID" -p "$AZURE_SECRET" --tenant "$AZURE_TENANT_ID" >/dev/null; then
    echo "Azure CLI login failed. Retrying in 10 minutes..."
    sleep 600
    continue
  fi

  # Ensure the A record-set exists
  if ! az network dns record-set a show \
      --resource-group "$RESOURCE_GROUP" \
      --zone-name "$DNS_ZONE_NAME" \
      --name "$MAIN_RECORD_NAME" >/dev/null 2>&1; then
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
    echo "A record ${FULL_MAIN_NAME} already set to $CURRENT_IP."
  else
    # Clear existing A records then add the current IP to avoid array index issues
    az network dns record-set a remove-record \
      --resource-group "$RESOURCE_GROUP" \
      --zone-name "$DNS_ZONE_NAME" \
      --record-set-name "$MAIN_RECORD_NAME" \
      --ipv4-address "$EXISTING_IP" >/dev/null 2>&1 || true

    az network dns record-set a add-record \
      --resource-group "$RESOURCE_GROUP" \
      --zone-name "$DNS_ZONE_NAME" \
      --record-set-name "$MAIN_RECORD_NAME" \
      --ipv4-address "$CURRENT_IP" >/dev/null

    echo "Updated A record ${FULL_MAIN_NAME} to $CURRENT_IP."
  fi

  # Manage CNAMEs pointing to the main record
  if [[ -n "${CNAME_NAMES:-}" ]]; then
    IFS=',' read -r -a cname_array <<< "$CNAME_NAMES"
    for cname in "${cname_array[@]}"; do
      cname_trimmed="$(echo "$cname" | xargs)"
      [[ -z "$cname_trimmed" ]] && continue

      # Ensure CNAME record-set exists
      if ! az network dns record-set cname show \
          --resource-group "$RESOURCE_GROUP" \
          --zone-name "$DNS_ZONE_NAME" \
          --name "$cname_trimmed" >/dev/null 2>&1; then
        az network dns record-set cname create \
          --resource-group "$RESOURCE_GROUP" \
          --zone-name "$DNS_ZONE_NAME" \
          --name "$cname_trimmed" \
          --ttl 300 >/dev/null
      fi

      # Set/overwrite the CNAME target to the full main record
      az network dns record-set cname set-record \
        --resource-group "$RESOURCE_GROUP" \
        --zone-name "$DNS_ZONE_NAME" \
        --record-set-name "$cname_trimmed" \
        --cname "$FULL_MAIN_NAME" >/dev/null

      echo "Ensured CNAME ${cname_trimmed}.${DNS_ZONE_NAME} -> ${FULL_MAIN_NAME}."
    done
  fi

  # Sleep for 10 minutes before repeating
  sleep 600
done