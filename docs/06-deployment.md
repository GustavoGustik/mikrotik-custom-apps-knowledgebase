# Deployment Guide

Step-by-step guide to deploying a custom app on RouterOS 7.22+.

## Prerequisites Checklist

Before deploying, verify:

```
/system/resource print          # ARM64 or x86, RouterOS 7.22+
/system/device-mode/print       # container: yes
/disk/print                     # External disk mounted
/app/settings print             # Disk, router IP, bridge configured
```

## Method 1: Inline YAML (Quick)

Paste YAML directly in the terminal:

```
/app add disabled=no network=bridge1 yaml="
name: myapp
descr: My custom application
category: productivity
services:
  web:
    image: docker.io/nginx:alpine
    ports:
      - 8080:80:web
    volumes:
      - data:/usr/share/nginx/html
    restart: unless-stopped
volumes:
  data: {}
"
```

**Tips**:
- Escape quotes in YAML with backslash or use single quotes
- `disabled=no` starts the app immediately
- `network=bridge1` overrides the default internal mode

## Method 2: File Upload via SCP

### 1. Create YAML file locally

```yaml
# myapp.app.yml
name: myapp
descr: My custom application
services:
  web:
    image: docker.io/nginx:alpine
    ports:
      - "8080:80:web"
    restart: unless-stopped
```

### 2. Upload to router

```bash
scp myapp.app.yml admin@10.0.1.1:/
```

### 3. Register the app

```
/app add disabled=yes network=bridge1 yaml=[/file get myapp.app.yml contents]
```

### 4. Configure static DHCP lease (for bridge1 mode)

```
# Enable temporarily to create VETH
/app enable myapp
# Wait a moment, then get MAC
/interface/veth/print where name~"myapp"
# Create lease
/ip/dhcp-server/lease/add address=10.0.1.60 mac-address=<MAC> server=dhcp1 comment="app-myapp"
# Restart to pick up new IP
/app disable myapp
/app enable myapp
```

### 5. Clean up uploaded file

```
/file remove myapp.app.yml
```

## Method 3: WinBox GUI

1. Open WinBox → **Apps** (or **Containers** → **Apps**)
2. Click **+** (Add)
3. Paste YAML in the editor
4. Set **Network** = `bridge1` (or leave default for internal)
5. Click **OK**
6. Select the app → **Enable**

**Note**: YAML cannot be edited after creation in WinBox. You must remove and recreate the app.

## Method 4: App Catalog

For built-in catalog apps:

1. Open WinBox → **Apps**
2. Browse categories or search
3. Click the app → **Install**
4. Configure environment variables if needed
5. Enable

## Deployment Workflow (Production)

### Step 1: Prepare YAML

Write your YAML manifest following the [YAML Reference](03-yaml-reference.md). Validate with the JSON schema.

### Step 2: Deploy Disabled

```
/app add disabled=yes network=bridge1 yaml="<your-yaml>"
```

### Step 3: Verify App Created

```
/app print where name=myapp
# Should show X (disabled)
```

### Step 4: Configure Static IP (bridge1 mode)

```
# Enable temporarily
/app enable myapp

# Wait for VETH creation (5-10 seconds)
/interface/veth/print where name~"myapp"

# Note the MAC address and create lease
/ip/dhcp-server/lease/add address=10.0.1.XX mac-address=AA:BB:CC:DD:EE:FF server=dhcp1 comment="app-myapp"

# Restart to pick up new IP
/app disable myapp
/app enable myapp
```

### Step 5: Wait for Image Pull

First deployment downloads images from registry. Monitor progress:

```
/app print follow-only where name=myapp
```

Or check container status:

```
/container print where name~"myapp"
```

States: `E` (downloading), `N` (starting), `R` (running), `H` (healthy)

### Step 6: Verify App Running

```
/app print where name=myapp
# Should show R (running) and UI-URL

/container print where name~"myapp"
# All containers should be R (running)
```

### Step 7: Test Access

- Open the UI URL in browser
- Check logs: `/container/log print where name~"myapp"`
- Test from LAN device

### Step 8: Test Reboot Survival

```
/system reboot
```

After reboot, verify:
- App auto-starts
- IP address is stable (check DHCP lease)
- All services running
- Data persisted (check volumes)

## Deploying Multi-Service Apps

Multi-service apps follow the same process but with additional considerations:

### Startup Order

Use `depends_on` to control order:

```yaml
services:
  database:
    image: docker.io/postgres:16-alpine
    # Starts first
  backend:
    depends_on:
      - database
    # Starts after database container starts (NOT after it's ready)
  frontend:
    depends_on:
      - backend
    # Starts after backend
```

### Database Connection Strings

All services share localhost. Use `127.0.0.1` in connection strings:

```yaml
environment:
  DATABASE_URL: postgresql://user:pass@127.0.0.1:5432/mydb
  REDIS_URL: redis://127.0.0.1:6379
  MONGO_HOST: 127.0.0.1
```

**Warning**: Do NOT use Docker-style service names (`postgres:5432`). While hostname resolution works (via `/etc/hosts`), it resolves to the same IP as localhost. Using `127.0.0.1` is more explicit and avoids confusion.

## Deploying Custom Code Apps

Two approaches for running your own code:

### Approach A: Custom Docker Image

Build and push to a registry:

```bash
# Build for ARM64
docker buildx build --platform linux/arm64 -t docker.io/yourusername/myapp:v1.0 --push .
```

Use in YAML:
```yaml
services:
  app:
    image: docker.io/yourusername/myapp:v1.0
```

### Approach B: Generic Image + Volume Mount

Use a base image (e.g., `node:20-alpine`) and mount your code:

```yaml
services:
  app:
    image: docker.io/node:20-alpine
    command: "node /app/dist/index.js"
    volumes:
      - app:/app
```

Upload code via SCP:
```bash
scp -r ./dist admin@10.0.1.1:/nvme1/apps/myapp/app/dist/
scp package.json admin@10.0.1.1:/nvme1/apps/myapp/app/
```

Install dependencies inside container:
```
/container/shell app-myapp
cd /app && npm install --production
```

## IP Address Planning

Recommended IP allocation for apps on bridge1:

| IP | App | Purpose |
|----|-----|---------|
| 10.0.1.1 | Router | Management |
| 10.0.1.15 | sia-gateway | Alarm receiver |
| 10.0.1.16 | hue-loxone-bridge | Home automation |
| 10.0.1.50 | mosquitto | MQTT broker |
| 10.0.1.51 | zigbee2mqtt | Zigbee bridge |
| 10.0.1.52 | nodered | Automation |
| 10.0.1.54 | unifi | WiFi controller |
| 10.0.1.55 | mqtt-logger | Monitoring |
| 10.0.1.100 | mikrotik-controller | Router management |

Reserve a range (e.g., .50-.120) for app IPs, keep it away from DHCP pool range.
