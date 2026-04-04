# Operations Guide

Day-to-day management, updates, backup, and restore procedures.

## Status Monitoring

### List All Apps
```
/app print
```

### App Flags

| Flag | Meaning | Description |
|------|---------|-------------|
| `X` | DISABLED | App is registered but not running |
| `R` | RUNNING | App is active with all containers running |
| `c` | CUSTOM | App was created via `/app add yaml="..."` |
| `s` | FROM-APP-STORE | App was installed from a custom app-store URL |

### The `c` Flag is Unreliable (RouterOS 7.22)

**The `c` (CUSTOM) flag does NOT survive a router reboot.** After restart, all apps lose the flag and appear identical to built-in catalog apps. Verified on RouterOS 7.22.1 stable (CCR2116-12G-4S+).

Additionally:
- Apps without `c` are treated as "builtin" — `/app/remove` refuses with `cannot remove builtin app`
- The flag cannot be set or restored manually
- It may be fixed in future RouterOS versions, but as of 7.22 it's ephemeral

**Since you can't rely on the flag, use these approaches to distinguish custom from catalog apps:**

**1. Naming convention** — prefix custom app names:
```yaml
name: custom-sia-gateway      # clearly custom
name: custom-hue-bridge       # clearly custom
name: mosquitto                # clearly from catalog
```

**2. Description prefix** — use the `descr` field:
```yaml
descr: "[CUSTOM] SIA DC-09 alarm receiver with MQTT and web UI"
```

**3. Maintain a list** — keep a record of your custom apps in git or on the router:
```bash
# Create a reference file on the router
/file/add name=custom-apps.txt contents="hue-loxone-bridge\nmikrotik-controller\nmqtt-logger\nsia-gateway\nunifi"
```

**4. Category convention** — use non-standard categories for custom apps so they group separately in WinBox.

### Detailed Status
```
/app print detail where name=myapp
# Shows: containers, IP, ports, status, memory, disk usage
```

### Container-Level Status
```
/container print where name~"myapp"
# Flags: S=stopped, N=starting, R=running, E=downloading, H=healthy
# Shows: memory-current, cpu-usage, image-id
```

### Live Monitoring
```
/app print follow-only where !disabled
```

### Check Resource Usage
```
# Per-app memory
/app print detail where !disabled
# Look for memory-current= and app-size= fields

# Total container memory
/container/config print
# Shows memory-current (total across all containers)
```

## Starting and Stopping

### Enable/Disable App (Full Lifecycle)
```
/app enable myapp      # Creates infra, pulls images, starts containers
/app disable myapp     # Stops containers, removes infra, preserves data
```

### Stop/Start Containers (Quick)
```
# Stop specific container
/container/stop [find where name~"myapp"]

# Start specific container
/container/start [find where name~"myapp"]
```

**Important**: There is NO `/container/restart` command. Use stop then start:
```
/container/stop [find where name="app-myapp"]
# Wait for container to stop
/container/start [find where name="app-myapp"]
```

### Restart All Services in an App
```
/app disable myapp
# Wait a moment
/app enable myapp
```

## Container Logs

```
# View recent logs
/container/log print where name~"myapp"

# Follow logs
/container/log print follow-only where name~"myapp"
```

**Limitation**: Only ~100 log messages retained per container.

### Interactive Shell
```
/container/shell app-myapp
```

Use for debugging, checking files, running commands inside the container.

## Updating Apps

### Strategy 1: Fixed Tags (Recommended for Production)

Pin exact image versions in YAML:

```yaml
image: mongo:4.4.18              # Exact patch version
image: docker.io/postgres:16.7-alpine  # Exact minor
image: ghcr.io/koenkk/zigbee2mqtt:2.9.1  # Exact app version
```

To update:
1. Disable app: `/app disable myapp`
2. Remove app: `/app remove myapp`
3. Edit YAML with new version
4. Recreate: `/app add disabled=no network=bridge1 yaml="<updated-yaml>"`

### Strategy 2: Manual Pull (Latest Tag)

If using `:latest` tag:

```
# Upgrade specific app
/app/upgrade myapp
```

Or at container level:
```
/container/stop [find where name="app-myapp"]
/container/repull [find where name="app-myapp"]
# Wait for download to complete
/container/start [find where name="app-myapp"]
```

### Strategy 3: Auto-Update

Enable automatic updates:
```
/app/set myapp auto-update=yes
```

Or globally:
```
/app/settings set auto-update=yes
```

**Warning**: Auto-update with `:latest` can cause breaking changes. Only use for non-critical apps.

## Backup

### RouterOS Export (App Definitions Only)
```
/export file=backup-apps
```

This exports app definitions (YAML, network settings) but NOT container data/volumes.

### Volume Backup (Data)
```bash
# Backup specific app volumes
scp -r admin@10.0.1.1:/nvme1/apps/myapp/ ./backup-myapp/

# Backup all app data
scp -r admin@10.0.1.1:/nvme1/apps/ ./backup-all-apps/
```

### Full Backup Procedure
```bash
# 1. Export RouterOS config
ssh admin@10.0.1.1 '/export' > routeros-config.rsc

# 2. Backup app data
scp -r admin@10.0.1.1:/nvme1/apps/ ./apps-backup/

# 3. Store YAML files in git (recommended)
git add -A && git commit -m "backup: app configs $(date +%Y-%m-%d)"
```

### App-Specific Backups

**UniFi**: Settings → System → Backup (downloads `.unf` file with all WiFi configs)

**Zigbee2MQTT**: Backup `z2m_data` volume (contains `configuration.yaml`, device database, coordinator backup)

**PostgreSQL databases**: Use `pg_dump` inside container:
```
/container/shell app-myapp-postgres
pg_dump -U myuser mydb > /var/lib/postgresql/data/backup.sql
```

Then copy:
```bash
scp admin@10.0.1.1:/nvme1/apps/myapp/pg_data/pgdata/backup.sql ./
```

## Restore

### From Volume Backup

1. Create app with same YAML: `/app add disabled=yes network=bridge1 yaml="..."`
2. Upload volume data:
   ```bash
   scp -r ./backup-myapp/data/ admin@10.0.1.1:/nvme1/apps/myapp/data/
   ```
3. Enable app: `/app enable myapp`

### From RouterOS Export

```
/import routeros-config.rsc
# Then pull images and start apps
/app enable myapp
```

## Changing App Configuration

**YAML cannot be edited in-place.** To change configuration:

1. Backup volume data
2. Disable: `/app disable myapp`
3. Remove: `/app remove myapp`
4. Cleanup (optional, only if changing volumes): `/app cleanup myapp`
5. Add with new YAML: `/app add disabled=yes network=bridge1 yaml="<new-yaml>"`
6. If cleaned up, restore volume data
7. Enable: `/app enable myapp`

### Changing Environment Variables (Without Recreating)

For simple env var changes:
```
/app/set myapp environment=<service>:<KEY>=<value>
```

## RouterOS Upgrade Impact

When upgrading RouterOS:
- App definitions survive (stored in running config)
- Container images cached on external storage (untouched)
- Volume data persists on external storage
- VETH MACs stable across reboot (but verify DHCP leases)
- Verify apps start correctly after upgrade

### Pre-Upgrade Checklist
1. Backup all volumes
2. Export RouterOS config
3. Note all app IPs and VETH MACs
4. Test apps after upgrade
5. If CRL errors on image pull: `/certificate/settings/set crl-use=no`

## Common Operational Tasks

### Check Disk Usage
```
/app print detail where name=myapp
# app-size=961.2MiB data-size=553.3MiB
```

### Check Memory Usage
```
/app print detail where name=myapp
# memory-current=1414.1MiB
```

### List All Container IPs
```
/app print where !disabled
# Shows IP-ADDRESS column
```

### View DHCP Leases for Apps
```
/ip/dhcp-server/lease/print where comment~"app-"
```

### Force Re-Pull Image
```
/container/stop [find where name="app-myapp"]
/container/repull [find where name="app-myapp"]
```
