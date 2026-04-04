# Backup and Restore

## What Needs to Be Backed Up

Custom apps have **4 layers** that all need independent backup:

| Layer | What | Where | How to Backup |
|-------|------|-------|--------------|
| **1. YAML definitions** | App structure, services, images, ports, env vars | Inside `/app` (not exported in 7.22!) | Extract from `/app print detail` |
| **2. Volume data** | Databases, config files, user uploads | `/<disk>/apps/<app-name>/` | SCP or rsync |
| **3. RouterOS config** | DHCP leases, firewall rules, VETH settings | Running config | `/export` |
| **4. App settings** | network=, use-https=, pvid= | `/app` properties | `/app/export` |

### Critical: `/app/export` is Broken in 7.22

**`/app/export` does NOT export YAML definitions.** It only saves `set` commands (enable/disable, network, use-https). This means:

```
# This DOES NOT save your YAML:
/app/export file=backup    # Only saves: /app/set myapp disabled=no network=bridge1

# Your YAML definitions are NOT in /export either:
/export file=full-backup   # Contains everything EXCEPT app YAML
```

If you lose the YAML, you lose the entire app definition — images, ports, environment variables, configs, volumes, depends_on — everything. **You must back up YAML separately.**

This is fixed in RouterOS 7.23 (`fixed YAML not exported for custom apps`).

## Backup Strategy

### Option 1: Automated Script on Proxmox/Linux (Recommended)

Use the provided [`backup-apps.sh`](../scripts/backup-apps.sh) script on your Proxmox host:

```bash
# One-time setup
mkdir -p /opt/mikrotik-backup
cp scripts/backup-apps.sh /opt/mikrotik-backup/
apt install sshpass  # if not installed

# Configure (edit the script or use env vars)
export ROUTER=192.168.128.1
export SSH_USER=admin
export SSH_PASS=your-password
export BACKUP_DIR=/opt/mikrotik-backup

# Run manually
/opt/mikrotik-backup/backup-apps.sh

# Schedule daily at 3 AM
echo '0 3 * * * /opt/mikrotik-backup/backup-apps.sh >> /var/log/mikrotik-backup.log 2>&1' | crontab -
```

The script backs up all 4 layers:
1. Extracts YAML from each running app via `/app print detail`
2. Rsyncs volume data from `/<disk>/apps/`
3. Exports full RouterOS config
4. Exports app settings and DHCP leases

Output structure:
```
/opt/mikrotik-backup/
├── 2026-04-04_0300/
│   ├── config/
│   │   ├── routeros-export.rsc      # Full RouterOS config
│   │   ├── app-export.rsc           # App enable/disable/network settings
│   │   └── dhcp-leases.rsc          # DHCP static leases
│   ├── yaml/
│   │   ├── mosquitto.app.yml        # Extracted YAML definitions
│   │   ├── zigbee2mqtt.app.yml
│   │   ├── unifi.app.yml
│   │   └── ...
│   └── data/
│       ├── mosquitto/               # Volume data
│       ├── zigbee2mqtt/
│       ├── unifi/
│       └── ...
├── 2026-04-03_0300/
│   └── ...
└── latest -> 2026-04-04_0300/       # Symlink to newest
```

### Option 2: Manual Backup

#### Back up YAML definitions

Extract each app's YAML individually:

```bash
# From your workstation/Proxmox
for APP in mosquitto zigbee2mqtt unifi sia-gateway hue-loxone-bridge mikrotik-controller mqtt-logger; do
  ssh admin@192.168.128.1 "/app/print detail where name=\"$APP\" and !disabled" \
    | sed -n '/yaml=/,/cmds=/p' \
    | sed '1s/.*yaml=//' | sed '$d' | sed 's/^        //' \
    > "$APP.app.yml"
  echo "Saved: $APP.app.yml"
done
```

Or store them in git (recommended):
```bash
git init mikrotik-apps && cd mikrotik-apps
# Save YAMLs as above
git add *.app.yml && git commit -m "backup: $(date +%Y-%m-%d)"
```

#### Back up volume data

```bash
# All apps at once
scp -r admin@192.168.128.1:/nvme1/apps/ ./apps-backup/

# Specific app
scp -r admin@192.168.128.1:/nvme1/apps/unifi/ ./unifi-backup/
```

#### Back up RouterOS config

```bash
ssh admin@192.168.128.1 '/export' > routeros-config.rsc
ssh admin@192.168.128.1 '/app/export' > app-settings.rsc
```

### Option 3: App-Specific Backups

Some apps have their own backup mechanisms that produce smaller, more portable backups:

| App | Built-in Backup | Command/Location |
|-----|----------------|------------------|
| **UniFi** | `.unf` file | Settings → System → Backup (in web UI) |
| **PostgreSQL** | `pg_dump` | `/container/shell app-<name>-postgres` → `pg_dump -U user db > /backup.sql` |
| **Node-RED** | Flow export | Menu → Export → All flows (JSON) |
| **Zigbee2MQTT** | Config + device DB | `/<disk>/apps/zigbee2mqtt/z2m_data/` (configuration.yaml + database.db) |

## Restore Procedure

### Full Restore (From Automated Backup)

```bash
BACKUP="/opt/mikrotik-backup/latest"
ROUTER="192.168.128.1"

# 1. Upload YAML files to router
scp $BACKUP/yaml/*.app.yml admin@$ROUTER:/

# 2. Register each app
ssh admin@$ROUTER '
/app add disabled=yes network=bridge1 yaml=[/file get mosquitto.app.yml contents]
/app add disabled=yes network=bridge1 yaml=[/file get zigbee2mqtt.app.yml contents]
/app add disabled=yes network=bridge1 yaml=[/file get unifi.app.yml contents]
# ... repeat for each app
'

# 3. Restore volume data
scp -r $BACKUP/data/mosquitto/ admin@$ROUTER:/nvme1/apps/mosquitto/
scp -r $BACKUP/data/zigbee2mqtt/ admin@$ROUTER:/nvme1/apps/zigbee2mqtt/
scp -r $BACKUP/data/unifi/ admin@$ROUTER:/nvme1/apps/unifi/
# ... repeat for each app

# 4. Apply settings
ssh admin@$ROUTER '
/app/set mosquitto use-https=no
/app/set zigbee2mqtt use-https=no
/app/set unifi use-https=no
# ... repeat for each app
'

# 5. Enable apps
ssh admin@$ROUTER '
/app/enable mosquitto
/app/enable zigbee2mqtt
/app/enable unifi
# ... repeat
'

# 6. Restore DHCP leases if needed
scp $BACKUP/config/dhcp-leases.rsc admin@$ROUTER:/
ssh admin@$ROUTER '/import dhcp-leases.rsc'

# 7. Clean up uploaded files
ssh admin@$ROUTER '/file/remove [find where name~".app.yml"]'
```

### Restore Order Matters

Some apps depend on others. Restore in this order:

1. **Infrastructure apps first**: Mosquitto (MQTT broker)
2. **Apps that depend on them**: Zigbee2MQTT, Node-RED (both need Mosquitto)
3. **Independent apps**: UniFi, Docmost, SIA Gateway, etc.

Wait for each app to fully start (check `/app print`) before enabling dependent apps.

## Backup Frequency Recommendations

| Data Type | Frequency | Reason |
|-----------|-----------|--------|
| YAML definitions | After every change | They rarely change, but loss is catastrophic |
| Volume data | Daily | Databases, configs change regularly |
| RouterOS config | Weekly + after changes | Stable, doesn't change often |
| PostgreSQL dumps | Daily | Point-in-time recovery capability |

## What Survives Without Backup

Even without backups, some things can be recovered:

- **Container images** — re-pulled from registry (just takes time/bandwidth)
- **Catalog app YAML** — built into RouterOS, always available
- **App infrastructure** (VETH, bridge ports, NAT rules) — auto-generated from YAML

**What CANNOT be recovered without backup**:
- Custom app YAML definitions (if not stored in git)
- Database contents (PostgreSQL, MongoDB, SQLite)
- App configuration files (Z2M device pairings, Node-RED flows, UniFi site config)
- User uploads and generated data
