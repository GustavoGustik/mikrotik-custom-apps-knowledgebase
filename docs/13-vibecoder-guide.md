# Vibecoder & AI Guide for MikroTik Custom Apps

Guide for AI-assisted development and "vibecoding" custom apps for MikroTik RouterOS 7.22+.

## What You Need to Know

You're building apps that run **on a router**, not on a server. The router runs containers via an orchestration system called `/app`. Think of it as a simplified, opinionated Docker Compose built into the router firmware.

### Key Constraints

1. **Architecture**: Your router is likely **ARM64** (Cortex-A72). Build images for `linux/arm64`.
2. **No build on device**: You CANNOT run `docker build` on the router. Build elsewhere, push to registry.
3. **No service DNS**: In multi-service apps, use `127.0.0.1` NOT service names for connections.
4. **No bind mounts**: Only named volumes. Code goes on a volume or in a custom image.
5. **Limited logs**: Only ~100 log lines per container. Add your own logging.
6. **No rootless**: All containers run as root.
7. **YAML only**: No Dockerfile, no docker-compose.yml — RouterOS has its own YAML format.

## Quick Start Template

### Simple Web App

```yaml
name: my-vibecoded-app
descr: My AI-generated web application
page: https://github.com/me/myapp
category: productivity
default-credentials: admin:password
services:
  app:
    image: docker.io/me/myapp:latest
    ports:
      - "3000:3000:web"
    environment:
      NODE_ENV: production
      TZ: Europe/Prague
    volumes:
      - data:/app/data
    restart: unless-stopped
volumes:
  data: {}
```

### Web App + Database

```yaml
name: my-fullstack-app
descr: Full-stack app with PostgreSQL
category: productivity
default-credentials: web setup
services:
  db:
    image: docker.io/postgres:16-alpine
    environment:
      POSTGRES_DB: myapp
      POSTGRES_USER: myapp
      POSTGRES_PASSWORD: change-me-in-production
      PGDATA: /var/lib/postgresql/data/pgdata
    volumes:
      - db_data:/var/lib/postgresql/data
    shm_size: "256mb"
    restart: unless-stopped
  app:
    image: docker.io/me/myapp:latest
    ports:
      - "3000:3000:web"
    environment:
      DATABASE_URL: postgresql://myapp:change-me-in-production@127.0.0.1:5432/myapp
      NODE_ENV: production
    depends_on:
      - db
    restart: unless-stopped
volumes:
  db_data: {}
```

### App + Database + Reverse Proxy

```yaml
name: my-pro-app
descr: Production app with Caddy reverse proxy
category: productivity
services:
  database:
    image: docker.io/postgres:16-alpine
    environment:
      POSTGRES_DB: myapp
      POSTGRES_USER: myapp
      POSTGRES_PASSWORD: SecurePass123!
      PGDATA: /var/lib/postgresql/data/pgdata
    volumes:
      - pg_data:/var/lib/postgresql/data
    shm_size: "256mb"
    restart: unless-stopped
  backend:
    image: docker.io/me/myapp-backend:latest
    depends_on:
      - database
    environment:
      DATABASE_URL: postgresql://myapp:SecurePass123!@127.0.0.1:5432/myapp
      NODE_ENV: production
      PORT: "3000"
    restart: unless-stopped
  caddy:
    image: docker.io/caddy:2-alpine
    depends_on:
      - backend
    ports:
      - "80:80:web"
    command: "caddy reverse-proxy --from :80 --to backend:3000"
    volumes:
      - caddy_data:/data
    restart: unless-stopped
volumes:
  pg_data: {}
  caddy_data: {}
```

## Development Workflow

### Option A: Custom Docker Image (Recommended)

1. **Build your app locally**
2. **Create a Dockerfile** (multi-stage for small images):
   ```dockerfile
   FROM node:20-alpine AS builder
   WORKDIR /app
   COPY package*.json ./
   RUN npm ci
   COPY . .
   RUN npm run build && npm prune --production
   
   FROM node:20-alpine
   WORKDIR /app
   COPY --from=builder /app/dist ./dist
   COPY --from=builder /app/node_modules ./node_modules
   EXPOSE 3000
   CMD ["node", "dist/index.js"]
   ```
3. **Build for ARM64 and push**:
   ```bash
   docker buildx build --platform linux/arm64 \
     -t docker.io/you/myapp:v1.0 --push .
   ```
4. **Deploy on router**:
   ```
   /app add disabled=no network=bridge1 yaml="<your-yaml>"
   ```

### Option B: Generic Image + Volume (Quick & Dirty)

No Docker build needed. Upload code directly:

1. **Write your YAML** with generic base image:
   ```yaml
   services:
     app:
       image: docker.io/node:20-alpine
       command: "node /app/index.js"
       volumes:
         - app:/app
   ```
2. **Deploy the app** (disabled):
   ```
   /app add disabled=yes network=bridge1 yaml="..."
   /app enable myapp  # Creates volume directories
   ```
3. **Upload your code** via SCP:
   ```bash
   scp -r ./dist admin@10.0.1.1:/nvme1/apps/myapp/app/
   scp package.json admin@10.0.1.1:/nvme1/apps/myapp/app/
   ```
4. **Install dependencies** inside container:
   ```
   /container/shell app-myapp
   cd /app && npm install --production
   exit
   ```
5. **Restart**:
   ```
   /container/stop [find where name="app-myapp"]
   /container/start [find where name="app-myapp"]
   ```

## Common Patterns for AI-Generated Apps

### Pattern 1: REST API + Database

Most common pattern. Node.js/Python backend with PostgreSQL:

```yaml
services:
  db:
    image: docker.io/postgres:16-alpine
    environment:
      POSTGRES_DB: api
      POSTGRES_USER: api
      POSTGRES_PASSWORD: secret
    volumes:
      - db:/var/lib/postgresql/data
    shm_size: "256mb"
  api:
    image: docker.io/you/api:v1
    ports:
      - "3000:3000:web"
    environment:
      DATABASE_URL: postgresql://api:secret@127.0.0.1:5432/api
    depends_on:
      - db
```

### Pattern 2: MQTT-Connected IoT App

App that subscribes to MQTT broker and processes messages:

```yaml
services:
  processor:
    image: docker.io/you/mqtt-processor:v1
    environment:
      MQTT_BROKER: mqtt://10.0.1.50:1883
      MQTT_TOPICS: "sensor/#,device/#"
    volumes:
      - data:/app/data
```

### Pattern 3: Monitoring Dashboard

Collect data and show on web UI:

```yaml
services:
  app:
    image: docker.io/you/dashboard:v1
    ports:
      - "3000:3000:web"
    environment:
      ROUTER_API: http://10.0.1.1/rest
      ROUTER_USER: api-user
      ROUTER_PASS: api-password
```

### Pattern 4: Background Worker + Web UI

Shared image, different commands:

```yaml
services:
  worker:
    image: docker.io/you/myapp:v1
    command: "node dist/worker.js"
    environment:
      MODE: worker
  web:
    image: docker.io/you/myapp:v1
    ports:
      - "3000:3000:web"
    environment:
      MODE: web
    depends_on:
      - worker
```

## AI Prompt Templates

### For ChatGPT/Claude: "Create a MikroTik Custom App"

> I need a MikroTik RouterOS Custom App YAML manifest for [describe app].
> 
> Requirements:
> - RouterOS 7.22+ Custom App format (NOT docker-compose)
> - ARM64 architecture (CCR2116 router)
> - Use `127.0.0.1` for inter-service communication (NOT service names)
> - Include `:web` label on the main HTTP port
> - Full registry prefix on all images (docker.io/, ghcr.io/)
> - `restart: unless-stopped` on all services
> - Named volumes for persistent data
> - Include metadata: name, descr, category, default-credentials
> 
> [Describe your app's functionality]

### For Generating Dockerfile

> Create a Dockerfile for my [Node.js/Python/Go] app that:
> - Uses multi-stage build
> - Targets `linux/arm64` (ARM64)
> - Uses Alpine base for small size
> - Includes health check endpoint at /health
> - Production-ready (no dev dependencies)
> 
> App entry point: [describe]
> Dependencies: [list]

## Gotchas for AI/Vibecoders

### 0. Make Custom Apps Distinguishable + Disable HTTPS

RouterOS has a `c` (CUSTOM) flag but it **doesn't survive reboots** (RouterOS 7.22). After restart, your custom app looks identical to the 90+ built-in catalog apps. Use naming conventions:

```yaml
# In your YAML — use a prefix so it's obvious in WinBox:
name: custom-my-app
descr: "[CUSTOM] My app description"
```

Deploy and immediately disable HTTPS:
```bash
/app add disabled=yes network=bridge1 yaml="<your-yaml>"
/app/set [find where name="custom-my-app"] use-https=no
/app/enable [find where name="custom-my-app"]
```

Why `use-https=no`: the default `yes` routes your app through `https://<app>.routingthecloud.com` which resolves to your public IP. Your custom LAN app lives at `http://10.0.1.50:3000` — the HTTPS domain is useless and makes `[accessIP]` return a domain instead of your LAN IP.

### 1. Database Hostnames DON'T Work Like Docker

```yaml
# WRONG (Docker Compose habit):
DATABASE_URL: postgresql://user:pass@database:5432/mydb

# RIGHT (RouterOS shared namespace):
DATABASE_URL: postgresql://user:pass@127.0.0.1:5432/mydb
```

### 2. Don't Use `:latest` in Production

```yaml
# RISKY:
image: docker.io/myapp:latest

# SAFE:
image: docker.io/myapp:2026-04-04-r1
```

### 3. The `:web` Label Matters

```yaml
# Without :web — no UI URL in WinBox:
ports:
  - "3000:3000"

# With :web — clickable URL appears:
ports:
  - "3000:3000:web"
```

### 4. MongoDB Version Lock on ARM Routers

```yaml
# WILL CRASH on CCR2116/CCR2216:
image: mongo:latest
image: mongo:4.4

# SAFE:
image: mongo:4.4.18
```

### 5. No Docker Compose `version:` Field

```yaml
# WRONG:
version: "3.8"
services: ...

# RIGHT (no version field):
name: myapp
services: ...
```

### 6. Remember External Storage

All data is on the router's external disk (NVMe/USB). The internal flash (128MB) is for RouterOS only.

### 7. Test Reboot Survival

After deploying, always reboot the router and verify everything comes back:
```
/system reboot
# Wait for reboot
/app print where name=myapp  # Should show R (running)
```

## Debugging

```bash
# SSH into router
ssh admin@10.0.1.1

# Check app status
/app print where name=myapp

# Check container status
/container print where name~"myapp"

# View logs
/container/log print where name~"myapp"

# Shell into container
/container/shell app-myapp

# Check networking
/interface/veth/print where name~"myapp"
/ip/dhcp-server/lease/print where comment~"myapp"
```

## RouterOS REST API

Your apps can talk to the router via REST API:

```
GET  http://10.0.1.1/rest/interface
GET  http://10.0.1.1/rest/ip/address
POST http://10.0.1.1/rest/tool/ping
```

Authentication: HTTP Basic Auth with RouterOS credentials.

This enables building monitoring dashboards, network management tools, and automation apps that interact with the router itself.
