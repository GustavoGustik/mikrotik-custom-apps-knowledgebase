#!/bin/bash
# =============================================================================
# MikroTik Custom Apps Backup Script
# Run this on your Proxmox host (or any Linux machine with SSH access to router)
#
# What it backs up:
#   1. RouterOS full config export
#   2. YAML definitions for all custom apps (extracted from /app print detail)
#   3. Volume data from /nvme1/apps/ (databases, configs, user data)
#   4. App settings and DHCP leases
#
# Why not just /app/export?
#   RouterOS 7.22 /app/export only saves enable/disable/network settings.
#   It does NOT export the YAML definitions! This is a known bug fixed in 7.23.
#
# Usage:
#   ./backup-apps.sh                    # backup with defaults
#   ROUTER=10.0.1.1 ./backup-apps.sh    # custom router IP
#
# Schedule with cron (daily at 3 AM):
#   0 3 * * * /opt/mikrotik-backup/backup-apps.sh >> /var/log/mikrotik-backup.log 2>&1
# =============================================================================

set -euo pipefail

# === Configuration ===
ROUTER="${ROUTER:-192.168.128.1}"
SSH_USER="${SSH_USER:-claude}"
SSH_PASS="${SSH_PASS:?Set SSH_PASS}"
BACKUP_DIR="${BACKUP_DIR:-/opt/mikrotik-backup}"
DISK="${DISK:-nvme1}"
KEEP_DAYS="${KEEP_DAYS:-30}"

# === Derived ===
DATE=$(date +%Y-%m-%d_%H%M)
TODAY_DIR="$BACKUP_DIR/$DATE"
LATEST_LINK="$BACKUP_DIR/latest"

echo "=== MikroTik App Backup: $DATE ==="
echo "Router: $ROUTER | Backup dir: $TODAY_DIR"

mkdir -p "$TODAY_DIR"/{config,yaml,data}

# --- 1. RouterOS full export ---
echo "[1/4] Exporting RouterOS config..."
sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no "$SSH_USER@$ROUTER" \
  '/export' > "$TODAY_DIR/config/routeros-export.rsc" 2>/dev/null

# --- 2. App export (settings only — no YAML in 7.22) ---
echo "[2/4] Exporting app settings..."
sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no "$SSH_USER@$ROUTER" \
  '/app/export' > "$TODAY_DIR/config/app-export.rsc" 2>/dev/null

# DHCP leases for app VETHs
sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no "$SSH_USER@$ROUTER" \
  '/ip/dhcp-server/lease/export' > "$TODAY_DIR/config/dhcp-leases.rsc" 2>/dev/null

# --- 3. Extract YAML definitions from /app print detail ---
echo "[3/4] Extracting YAML definitions..."

# Get list of enabled apps
APPS=$(sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no "$SSH_USER@$ROUTER" \
  '/app/print where !disabled proplist=name' 2>/dev/null \
  | grep -oP '(?<=R[c ]  )\S+' || true)

# Also try simpler parsing if grep -P not available
if [ -z "$APPS" ]; then
  APPS=$(sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no "$SSH_USER@$ROUTER" \
    '/app/print where !disabled proplist=name' 2>/dev/null \
    | awk '/^ *[0-9]+ R/ {print $NF}')
fi

for APP in $APPS; do
  echo "  Extracting YAML: $APP"
  sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no "$SSH_USER@$ROUTER" \
    "/app/print detail where name=\"$APP\" and !disabled" 2>/dev/null \
    | sed -n '/yaml=/,/cmds=/p' \
    | sed '1s/.*yaml=//' \
    | sed '$d' \
    | sed 's/^        //' \
    > "$TODAY_DIR/yaml/$APP.app.yml"

  # Also save network and use-https settings
  NET=$(sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no "$SSH_USER@$ROUTER" \
    "/app/print detail where name=\"$APP\" and !disabled" 2>/dev/null \
    | grep -o 'network=[^ ]*' | head -1)
  HTTPS=$(sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no "$SSH_USER@$ROUTER" \
    "/app/print detail where name=\"$APP\" and !disabled" 2>/dev/null \
    | grep -o 'use-https=[^ ]*' | head -1)
  echo "# Restore: /app add disabled=yes $NET yaml=[/file get $APP.app.yml contents]" \
    >> "$TODAY_DIR/yaml/$APP.app.yml"
  echo "# Then: /app/set $APP $HTTPS" >> "$TODAY_DIR/yaml/$APP.app.yml"
done

# --- 4. Rsync volume data ---
echo "[4/4] Syncing volume data (this may take a while)..."

# List app directories on the disk
APP_DIRS=$(sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no "$SSH_USER@$ROUTER" \
  "/file/print where name~\"$DISK/apps/\" and type=\"directory\" proplist=name" 2>/dev/null \
  | grep -oP "$DISK/apps/\S+" || true)

for DIR in $APP_DIRS; do
  APP_NAME=$(basename "$DIR")
  echo "  Syncing: $APP_NAME"
  mkdir -p "$TODAY_DIR/data/$APP_NAME"
  sshpass -p "$SSH_PASS" scp -o StrictHostKeyChecking=no -r \
    "$SSH_USER@$ROUTER:/$DIR/" "$TODAY_DIR/data/$APP_NAME/" 2>/dev/null || \
    echo "  WARNING: Failed to sync $APP_NAME (may have subdirectories)"
done

# --- Update latest symlink ---
rm -f "$LATEST_LINK"
ln -s "$TODAY_DIR" "$LATEST_LINK"

# --- Cleanup old backups ---
echo "Cleaning backups older than $KEEP_DAYS days..."
find "$BACKUP_DIR" -maxdepth 1 -type d -name "20*" -mtime +$KEEP_DAYS -exec rm -rf {} \;

# --- Summary ---
TOTAL_SIZE=$(du -sh "$TODAY_DIR" | cut -f1)
YAML_COUNT=$(ls "$TODAY_DIR/yaml/"*.yml 2>/dev/null | wc -l)
echo ""
echo "=== Backup complete ==="
echo "  Location: $TODAY_DIR"
echo "  Total size: $TOTAL_SIZE"
echo "  YAML files: $YAML_COUNT"
echo "  Symlink: $LATEST_LINK"
echo ""
echo "=== Restore instructions ==="
echo "  1. Upload YAML:  scp $TODAY_DIR/yaml/*.yml $SSH_USER@$ROUTER:/"
echo "  2. Add app:      /app add disabled=yes network=bridge1 yaml=[/file get <app>.app.yml contents]"
echo "  3. Restore data: scp -r $TODAY_DIR/data/<app>/ $SSH_USER@$ROUTER:/$DISK/apps/<app>/"
echo "  4. Set options:  /app/set <app> use-https=no"
echo "  5. Enable:       /app/enable <app>"
