# Troubleshooting

Common issues and solutions when working with MikroTik Custom Apps.

## Container Won't Start

### Symptom: Status shows E (Downloading) forever

**Cause**: Image pull failing (registry unreachable, rate limit, wrong image name)

**Fix**:
```
# Check container status
/container print where name~"myapp"
# Look for status flags: E=downloading, F=failed

# Check if registry is reachable
/tool/fetch url=https://registry-1.docker.io/v2/ mode=https

# If Docker Hub rate limited, use mirror
/app/settings set registry-mirrors=https://mirror.gcr.io

# If certificate error
/certificate/settings/set crl-use=no
```

### Symptom: Status shows F (Download Failed)

**Cause**: Image doesn't exist for ARM64, wrong image name, or registry auth failure

**Fix**:
```
# Verify image exists for your architecture
# Check on Docker Hub or registry that arm64 variant exists

# Try explicit registry
image: docker.io/library/postgres:16-alpine  # Not just postgres:16-alpine
```

### Symptom: Container starts then immediately stops

**Cause**: Application error inside container, wrong command, missing config

**Fix**:
```
# Check logs
/container/log print where name~"myapp"

# Get into container shell (if it stays running briefly)
/container/shell app-myapp

# Check if the entrypoint/command is correct
/container print detail where name~"myapp"
# Look at cmd= and entrypoint= fields
```

## App IP Changed After Reboot

**Cause**: DHCP assigned different IP (no static lease or MAC changed)

**Fix**:
```
# 1. Check current VETH MAC
/interface/veth/print where name~"myapp"

# 2. Check/update DHCP lease
/ip/dhcp-server/lease/print where comment~"myapp"

# 3. If MAC changed (after app recreation), update lease
/ip/dhcp-server/lease/set [find where comment~"myapp"] mac-address=<NEW-MAC>

# 4. Restart app
/app disable myapp
/app enable myapp
```

## "reverse-proxy: bind error: cannot bind to port 443"

**Cause**: Another service (WebFig, custom reverse proxy) is already using port 443

**Cause**: The `www-ssl` service (WebFig HTTPS) and `reverse-proxy` service (app HTTPS) both default to port 443. They can't share it — the first one to start wins.

**Fix** (recommended — do this once during initial setup):
```
# 1. Move WebFig HTTPS to port 8443
/ip/service/set www-ssl port=8443

# 2. Restart reverse-proxy to claim port 443
/ip/service/set reverse-proxy disabled=yes
/ip/service/set reverse-proxy disabled=no

# 3. Verify — errors should be gone
/ip/service/print where name=reverse-proxy
/app print where !disabled
```

WebFig remains accessible at `https://<router-ip>:8443`. Apps get HTTPS at `https://<name>.<device>.routingthecloud.com`.

See also: [Prerequisites — Step 5](02-prerequisites.md#step-5-free-port-443-for-app-reverse-proxy)

**Alternative per-app**: If you don't need HTTPS for a specific app:
```
/app/set myapp use-https=no
```

## "add bridge port failed: device already added as bridge port"

**Cause**: Duplicate app definition trying to use same VETH name

**Fix**:
```
# Find duplicate apps
/app print where name~"myapp"

# Remove the duplicate (disabled one)
/app remove [find where name="myapp" and disabled]
```

## Multi-Service App: Database Connection Refused

**Cause**: Using service name instead of localhost, or database not ready yet

**Fix**:

```yaml
# WRONG:
DATABASE_URL: postgresql://user:pass@postgres:5432/mydb

# RIGHT:
DATABASE_URL: postgresql://user:pass@127.0.0.1:5432/mydb
```

If timing issue (app starts before DB is ready):
```yaml
# Add depends_on
services:
  backend:
    depends_on:
      - database
    # Add retry logic in your app code
```

## MongoDB "Illegal Instruction" on CCR2116/CCR2216

**Cause**: MongoDB 4.4.19+ requires ARMv8.2-A, but Cortex-A72 only supports ARMv8.0-A

**Fix**: Pin MongoDB to exactly `4.4.18`:

```yaml
services:
  mongodb:
    image: mongo:4.4.18  # MUST be exact. Not :4.4, not :latest
```

## Image Pull Rate Limits

**Cause**: Docker Hub limits anonymous pulls to 100/6h

**Symptoms**:
- Container stuck in E (downloading) state
- `HTTP 429 Too Many Requests` in logs

**Fix**:
```
# Use registry mirror
/app/settings set registry-mirrors=https://mirror.gcr.io

# Or use alternative registries in YAML
image: ghcr.io/...     # GitHub (no limits for public)
image: lscr.io/...     # LinuxServer.io
image: quay.io/...     # Red Hat Quay
```

## App Disappeared After Reboot

**Cause**: Direct `/container` manipulation desynchronized `/app` system

**Fix**: This is difficult to recover. Prevention is key:
```
# NEVER do this on app-managed containers:
/container/remove <app-container>
/container/set <app-container> ...

# ONLY safe /container commands:
/container/stop <app-container>
/container/start <app-container>
/container/shell <app-container>
```

**Recovery**:
```
# 1. Check if orphaned containers exist
/container print

# 2. Stop and remove orphaned containers
/container/stop [find where name~"myapp"]
/container/remove [find where name~"myapp"]

# 3. Remove orphaned VETH
/interface/veth/remove [find where name~"myapp"]

# 4. Recreate app from YAML
/app add disabled=no network=bridge1 yaml="<yaml>"
```

## SSL/CRL Error During Image Pull

**Symptom**: `SSL: certificate verify failed` or CRL-related errors

**Fix**:
```
/certificate/settings/set crl-use=no
```

## Container Uses Too Much Memory

**Symptom**: Router becomes slow, other apps affected

**Note**: RouterOS doesn't enforce memory limits from YAML. Use `/container/config`:
```
/container/config set memory-high=2048MiB
```

This sets a global limit. Per-container limits are not available via YAML.

## MQTT Connection Issues (Z2M → Mosquitto)

**Checklist**:
1. Verify Mosquitto is running: `/app print where name=mosquitto`
2. Check Mosquitto IP: `/interface/veth/print where name~"mosquitto"`
3. Verify Z2M config: `serial.port` and `mqtt.server` settings
4. Test from router: `/tool/fetch url=http://10.0.1.50:1883 mode=http`
5. Check both apps on same bridge (bridge1)

## Node-RED MQTT Nodes Stuck "Connecting"

**Fix**:
1. Check broker config in Node-RED UI (correct IP:port)
2. Verify Mosquitto allows anonymous: check mosquitto.conf
3. Ensure Node-RED and Mosquitto on same bridge
4. Restart Node-RED: `/container/stop [find where name="app-nodered"]` then start

## Disk Full

```
# Check disk usage
/disk/print detail

# Find large apps
/app print detail where !disabled
# Sort by app-size + data-size

# Clean unused layers
/app cleanup <unused-app>
# WARNING: This deletes ALL data for that app!
```

## Debug Checklist

When something doesn't work, check in this order:

1. **Is the app enabled?** `/app print where name=myapp`
2. **Are containers running?** `/container print where name~"myapp"`
3. **What do logs say?** `/container/log print where name~"myapp"`
4. **Is networking OK?** Check VETH, bridge port, IP address
5. **Can container reach network?** `/container/shell` then `ping` or `wget`
6. **Are ports mapped correctly?** Check `/ip/firewall/nat print` (internal mode)
7. **Is storage OK?** Check `/disk/print` for free space
8. **Did DHCP lease match?** Check `/ip/dhcp-server/lease/print`
