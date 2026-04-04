# Prerequisites

## Hardware Requirements

### Router
- **Architecture**: ARM64 or x86 (check with `/system/resource print`)
- **RAM**: Minimum 1 GB, recommended 4+ GB for multi-service apps
- **RouterOS**: 7.22+ (stable or testing channel)
- **Package**: `container.npk` must be installed

### Storage
- **External disk required**: NVMe, USB flash/SSD, or SD card
- **Filesystem**: ext4 (recommended) or btrfs
- **Minimum size**: 4 GB for light apps, 16+ GB recommended
- Internal NAND/flash (128 MB) is **NOT sufficient** for app storage

### Memory Guidelines

| Workload | RAM Needed | Examples |
|----------|-----------|---------|
| 1-2 light apps | 1 GB | Mosquitto, Pi-hole |
| 3-5 medium apps | 4 GB | Node-RED, Z2M, Mosquitto, Caddy |
| 5-10 mixed apps | 8 GB | Above + Docmost, SIA Gateway |
| 10+ apps with databases | 16 GB | Full stack: UniFi, databases, monitoring |

## Step 1: Install Container Package

If `container.npk` is not installed:

```
/system/package/print
```

Download from [mikrotik.com/download](https://mikrotik.com/download) for your architecture, upload to router, reboot.

## Step 2: Enable Container Mode

Container mode requires a device-mode change (physical confirmation or cold reboot):

```
/system/device-mode/update container=yes
```

After running this command:
- **On physical routers**: Press the reset button within 60 seconds, OR
- **On CHR**: Reboot the VM

Verify:
```
/system/device-mode/print
# Should show container: yes
```

## Step 3: Prepare External Storage

### Verify disk is mounted
```
/disk/print
```

### Format if needed (DESTROYS ALL DATA)
```
/disk/format-drive disk1 file-system=ext4 label=nvme1
```

### Verify space
```
/disk/print detail
# Check free-space
```

## Step 4: Run App Setup Wizard

The setup wizard configures disk, router IP, and bridge for the app system:

```
/app setup
```

This configures:
- **Disk**: Which external storage to use for app data
- **Router IP**: The IP address used for accessing apps (e.g., 10.0.1.1)
- **Bridge**: Which bridge apps connect to (typically `bridge1`)

### Verify setup
```
/app/settings print
```

Expected output:
```
              disk: nvme1
  assumed-router-ip: 10.0.1.1
         lan-bridge: bridge1
       auto-update: yes
  certificate-status: ok
         certificate: apps-*.xxx.routingthecloud.com
```

## Step 5: Free Port 443 for App Reverse Proxy

RouterOS uses port 443 for both `www-ssl` (WebFig HTTPS) and `reverse-proxy` (automatic HTTPS for apps). They can't share it — whichever starts first wins, the other fails with:

```
reverse-proxy: bind error: cannot bind to port 443: Address in use (12)
```

This error shows as a red warning on **every app** in WinBox/WebFig. Fix by moving WebFig HTTPS to a different port:

```
# Move WebFig HTTPS to port 8443
/ip/service/set www-ssl port=8443

# Restart the reverse-proxy service to claim port 443
/ip/service/set reverse-proxy disabled=yes
/ip/service/set reverse-proxy disabled=no

# Verify — no error should appear
/ip/service/print where name=reverse-proxy
/ip/reverse-proxy/print
```

After this, WebFig HTTPS is at `https://<router-ip>:8443` and apps get automatic HTTPS via `https://<app-name>.<device>.routingthecloud.com`.

**Alternative**: If you don't need HTTPS for apps, disable it per-app:
```
/app/set myapp use-https=no
```

## Step 6: Verify Container Configuration

```
/container/config print
```

Expected:
```
  assumed-registry-url: docker.io
              layer-dir:
                 tmpdir:
           memory-high: unlimited
```

## Step 6 (Optional): Configure Registry Mirrors

To avoid Docker Hub rate limits (100 pulls/6h for anonymous):

```
/app/settings set registry-mirrors=https://mirror.gcr.io
```

Or use alternative registries in your YAML:
- `ghcr.io/` — GitHub Container Registry (no rate limits for public images)
- `lscr.io/` — LinuxServer.io (mirrors popular images)
- `quay.io/` — Red Hat Quay

## Verification Checklist

```
# All of these should pass:
/system/resource print          # Verify ARM64 or x86
/system/device-mode/print       # container: yes
/disk/print                     # External disk mounted
/app/settings print             # Disk, IP, bridge configured
/container/config print         # Registry configured
```

Once all checks pass, you're ready to deploy your first app.
