# Real-World Examples

Example YAML manifests organized by type: catalog apps (ship with RouterOS) vs custom apps (user-written).

All examples use generic IP addresses (`10.0.1.0/24` for LAN, router at `10.0.1.1`). Replace with your actual subnet.

---

## Part 1: Catalog Apps (Built into RouterOS)

These apps come pre-installed in the RouterOS 7.22+ app catalog. You can install them with one click in WinBox, or customize the YAML as shown below.

### 1.1 Mosquitto — MQTT Broker with Inline Config

The simplest app pattern: single service with inline configuration file. Available in catalog but shown here with customized config.

```yaml
name: mosquitto
descr: Eclipse Mosquitto MQTT message broker
page: https://mosquitto.org
category: messaging
services:
  mosquitto:
    image: docker.io/eclipse-mosquitto:latest
    ports:
      - 1883:1883:mqtt
      - 9001:9001:websockets
    volumes:
      - data:/mosquitto/data
      - log:/mosquitto/log
    configs:
      - source: 'mosquitto_conf'
        target: '/mosquitto/config/mosquitto.conf'
    restart: unless-stopped
configs:
  'mosquitto_conf':
    content: |
      listener 1883
      allow_anonymous true

      listener 9001
      protocol websockets
      allow_anonymous true
```

**Pattern demonstrated**: Inline `configs:` section — inject config files directly from YAML without uploading separate files.

### 1.2 Node-RED — Minimal Single-Service App

The absolute minimum viable YAML. One image, one port, one volume.

```yaml
name: nodered
descr: Low-code programming for event-driven applications
page: https://nodered.org
category: automation
services:
  nodered:
    image: docker.io/nodered/node-red:latest
    ports:
      - 1880:1880:web
    volumes:
      - node_red_data:/data
    restart: unless-stopped
```

**Pattern demonstrated**: Minimal YAML — just `image`, `ports`, `volumes`, `restart`.

### 1.3 Docmost — Multi-Service Catalog App (Internal Network)

Three services (Postgres + Redis + Docmost) with placeholder variables. This is how it comes from the catalog — no changes needed.

```yaml
name: docmost
descr: Modern wiki and documentation platform built for teams
page: https://docmost.com
category: productivity
default-credentials: web setup
services:
  db:
    image: docker.io/postgres:16-alpine
    environment:
      POSTGRES_DB: docmost
      POSTGRES_USER: docmost
      POSTGRES_PASSWORD: STRONG_DB_PASSWORD
    volumes:
      - db_data:/var/lib/postgresql/data
    shm_size: "256mb"
  redis:
    image: docker.io/redis:7.2-alpine
    volumes:
      - redis_data:/data
  docmost:
    image: docker.io/docmost/docmost:latest
    environment:
      APP_URL: "[accessProto]://[accessIP]:[accessPort]"
      APP_SECRET: "REPLACE_WITH_LONG_SECRET_KEY_HERE"
      DATABASE_URL: "postgresql://docmost:STRONG_DB_PASSWORD@127.0.0.1:5432/docmost?schema=public"
      REDIS_URL: "redis://127.0.0.1:6379"
    ports:
      - 3013:3000:web
    volumes:
      - docmost:/app/data/storage
    restart: unless-stopped
```

**Pattern demonstrated**: Placeholder variables (`[accessProto]`, `[accessIP]`, `[accessPort]`) — RouterOS replaces them at runtime. `127.0.0.1` for inter-service DB/Redis communication. `shm_size` for PostgreSQL.

### 1.4 Zigbee2MQTT — Single-Service with External Dependency

Also from catalog, but depends on a separate Mosquitto app for MQTT.

```yaml
name: zigbee2mqtt
descr: Zigbee2MQTT bridge with web GUI
page: https://www.zigbee2mqtt.io/
category: home-automation
default-credentials: onboarding
url-path: /
auto-update: false
services:
  zigbee2mqtt:
    image: ghcr.io/koenkk/zigbee2mqtt:latest
    ports:
      - "8080:8080:web"
    environment:
      TZ: Europe/Prague
    volumes:
      - z2m_data:/app/data
    restart: unless-stopped
volumes:
  z2m_data: {}
```

**Pattern demonstrated**: Inter-app dependency — Z2M connects to Mosquitto at `mqtt://10.0.1.50:1883` (configured via onboarding wizard after first start, not in YAML). Apps communicate via LAN IPs, not through any shared namespace.

---

## Part 2: Custom Apps (User-Written YAML)

These apps are NOT in the RouterOS catalog. They demonstrate how to write your own YAML manifests for custom use cases.

### 2.1 UniFi — Custom Multi-Service with Version-Pinned Database

WiFi controller with MongoDB. Requires exact MongoDB version on ARM Cortex-A72.

```yaml
name: unifi
descr: UniFi Network Application for WiFi AP management
page: https://ui.com/
category: network
default-credentials: onboarding
url-path: /
auto-update: false
services:
  mongodb:
    image: mongo:4.4.18
    environment:
      MONGO_INITDB_ROOT_USERNAME: unifi
      MONGO_INITDB_ROOT_PASSWORD: unifi
    volumes:
      - unifi_db:/data/db
    restart: unless-stopped
  unifi:
    image: lscr.io/linuxserver/unifi-network-application:latest
    ports:
      - "8443:8443:web"
      - "8080:8080:tcp"
      - "3478:3478:udp"
      - "10001:10001:udp"
    environment:
      PUID: 1000
      PGID: 1000
      TZ: Europe/Prague
      MONGO_HOST: 127.0.0.1
      MONGO_PORT: 27017
      MONGO_DBNAME: unifi
      MONGO_USER: unifi
      MONGO_PASS: unifi
      MONGO_AUTHSOURCE: admin
      MEM_LIMIT: 1024
    volumes:
      - unifi_data:/config
    restart: unless-stopped
volumes:
  unifi_db: {}
  unifi_data: {}
```

**Pattern demonstrated**:
- **Version pinning**: `mongo:4.4.18` — MUST be exact on CCR2116/CCR2216 (Cortex-A72). Versions 4.4.19+ crash with "Illegal instruction"
- **Multi-service localhost**: `MONGO_HOST: 127.0.0.1` — both containers share one VETH
- **Multiple port types**: `:web` for admin UI, `:tcp` for AP inform, `:udp` for STUN and discovery

### 2.2 SIA Gateway — Generic Image + Custom Code on Volume

Custom alarm receiver. Uses `node:20-alpine` as base and loads application code from a volume.

```yaml
name: sia-gateway
descr: SIA DC-09 alarm receiver with MQTT, Loxone and web UI
page: https://example.com/sia-gateway
category: security
default-credentials: none
url-path: /
services:
  postgres:
    image: docker.io/postgres:16-alpine
    environment:
      POSTGRES_DB: sia_gateway
      POSTGRES_USER: sia
      POSTGRES_PASSWORD: change-me-in-production
      PGDATA: /var/lib/postgresql/data/pgdata
    volumes:
      - pg_data:/var/lib/postgresql/data
    restart: unless-stopped
  gateway:
    image: docker.io/node:20-alpine
    ports:
      - "5000:5000:sia-dc09"
      - "3000:3000:web"
    environment:
      NODE_ENV: production
      CONFIG_PATH: /app/config.json
      TZ: Europe/Prague
    command: "node /app/dist/index.js"
    volumes:
      - app:/app
    depends_on:
      - postgres
    restart: unless-stopped
volumes:
  pg_data: {}
  app: {}
```

Deploy code to volume:
```bash
scp -r ./dist admin@10.0.1.1:/nvme1/apps/sia-gateway/app/dist/
scp package.json admin@10.0.1.1:/nvme1/apps/sia-gateway/app/
```

**Pattern demonstrated**:
- **Generic image + volume**: No Docker build needed — use `node:20-alpine` and mount code
- **Custom command**: `command: "node /app/dist/index.js"` overrides default entrypoint
- **depends_on**: Database starts before application

### 2.3 Hue-Loxone Bridge — Custom Image with Inline JSON Config

Custom Docker image with embedded JSON configuration delivered via `configs:`.

```yaml
name: hue-loxone-bridge
descr: Bidirectional bridge between Philips Hue and Loxone Miniserver
page: https://example.com/hue-loxone-bridge
category: home-automation
default-credentials: none
url-path: /
auto-update: false
services:
  bridge:
    image: docker.io/youruser/hue-loxone-bridge:latest
    ports:
      - "3100:3000:web"
    environment:
      NODE_ENV: production
      TZ: Europe/Prague
    command: "node /app/index.js --config /data/config.json"
    volumes:
      - data:/data
    stop_grace_period: "10s"
    restart: unless-stopped
configs:
  'config_json':
    target_volume: data
    target_path: 'config.json'
    content: |
      {
        "server": { "port": 3000 },
        "hue": {
          "bridgeIP": "10.0.1.200",
          "appKey": "your-hue-api-key-here"
        },
        "loxone": {
          "host": "10.0.1.201",
          "port": 80,
          "user": "admin",
          "password": "your-password"
        },
        "mappings": [
          { "name": "Kitchen", "hueId": "xxx", "loxoneUuid": "yyy" }
        ]
      }
volumes:
  data: {}
```

**Pattern demonstrated**:
- **Custom Docker image**: Pre-built and pushed to registry
- **Inline JSON config**: `configs:` with `target_volume` + `target_path` writes config file into a volume
- **Custom command**: Passes config path as argument

### 2.4 MQTT Logger — Lightweight Custom Monitoring

Single-service Node.js app that subscribes to MQTT and logs to an external database.

```yaml
name: mqtt-logger
descr: MQTT traffic logger to PostgreSQL for analytics
page: https://example.com/mqtt-logger
category: monitoring
default-credentials: none
url-path: /
auto-update: false
services:
  logger:
    image: docker.io/node:20-alpine
    ports:
      - "3000:3000:web"
    environment:
      WEB_PORT: "3000"
      MQTT_BROKER: mqtt://10.0.1.50:1883
      DB_HOST: 10.0.1.1
      DB_PORT: "5432"
      DB_NAME: mqtt_logger
      DB_USER: mqtt_logger
      DB_PASSWORD: change-me
      MQTT_TOPICS: "#"
      SKIP_TOPICS: "zigbee/bridge/"
      BATCH_SIZE: "100"
      BATCH_INTERVAL_MS: "1000"
      NODE_ENV: production
      TZ: Europe/Prague
    command: "sh /app/entrypoint.sh"
    volumes:
      - app:/app
    restart: unless-stopped
volumes:
  app: {}
```

**Pattern demonstrated**:
- **External service references**: MQTT broker and PostgreSQL on different IPs (other apps or devices)
- **Shell entrypoint**: `command: "sh /app/entrypoint.sh"` for startup scripts
- **Filtering**: App-level topic filtering via environment variables

### 2.5 Multi-Router Controller — Complex 4-Service App

The most complex pattern: 4 services (database, API backend, background worker, reverse proxy) all sharing one IP.

```yaml
name: router-controller
descr: Centralized router management and monitoring platform
page: https://example.com/router-controller
icon: https://example.com/logo.svg
category: networking
default-credentials: admin / admin (change immediately!)
url-path: /
auto-update: false

services:
  # 1. Database — starts first
  database:
    image: docker.io/library/postgres:16-alpine
    container_name: ctrl-database
    hostname: postgres
    environment:
      POSTGRES_DB: controller
      POSTGRES_USER: controller
      POSTGRES_PASSWORD: SecureDbPass123!
      POSTGRES_INITDB_ARGS: --encoding=UTF8 --locale=C
      PGDATA: /var/lib/postgresql/data/pgdata
      TZ: Europe/Prague
    volumes:
      - pg_data:/var/lib/postgresql/data
    shm_size: "256mb"
    stop_grace_period: "30s"
    restart: unless-stopped

  # 2. API Backend — depends on database
  backend:
    image: docker.io/youruser/controller-backend:v1.0
    container_name: ctrl-backend
    hostname: backend
    depends_on:
      - database
    environment:
      NODE_ENV: production
      DATABASE_URL: postgresql://controller:SecureDbPass123!@localhost:5432/controller
      JWT_SECRET: replace-with-random-64-char-string
      JWT_EXPIRES_IN: 7d
      PORT: "3000"
      CORS_ORIGIN: "*"
      LOG_LEVEL: info
      TZ: Europe/Prague
    stop_grace_period: "10s"
    restart: unless-stopped

  # 3. Background Worker — same image, different command
  worker:
    image: docker.io/youruser/controller-backend:v1.0
    container_name: ctrl-worker
    hostname: worker
    depends_on:
      - database
      - backend
    environment:
      NODE_ENV: production
      DATABASE_URL: postgresql://controller:SecureDbPass123!@localhost:5432/controller
      WORKER_MODE: "true"
      MONITORING_INTERVAL: "30000"
      LOG_LEVEL: info
      TZ: Europe/Prague
    command: "node dist/workers/monitoring-worker.js"
    stop_grace_period: "10s"
    restart: unless-stopped

  # 4. Caddy Reverse Proxy — single entry point
  caddy:
    image: docker.io/library/caddy:2-alpine
    container_name: ctrl-caddy
    hostname: caddy
    depends_on:
      - backend
    ports:
      - "80:80:web"
    volumes:
      - caddy_data:/data
      - caddy_config:/config
    command: "caddy reverse-proxy --from :80 --to backend:3000"
    stop_grace_period: "5s"
    restart: unless-stopped

volumes:
  pg_data: {}
  caddy_data: {}
  caddy_config: {}
```

**Patterns demonstrated**:
- **4 services on 1 IP**: All share single VETH — Caddy forwards HTTP to backend via hostname
- **Shared image, different commands**: `worker` reuses `backend` image with `command: "node dist/workers/monitoring-worker.js"`
- **depends_on chain**: `database` → `backend` → `worker`, `backend` → `caddy`
- **Caddy as entry point**: Only Caddy exposes port 80 with `:web` label. Backend is not directly accessible.
- **`localhost` in DATABASE_URL**: Because all services share network namespace

---

## Memory and Disk Reference

Typical resource usage for these app types (measured on CCR2116-12G-4S+, ARM64):

```
App Type                Memory      Image Size   Notes
───────────────────────────────────────────────────────────────
MQTT broker             ~15 MB      ~25 MB       Extremely light
Zigbee bridge           ~100 MB     ~140 MB      Depends on device count
Node-RED                ~190 MB     ~600 MB      Grows with installed nodes
UniFi (MongoDB+app)     ~1,400 MB   ~960 MB      Heaviest — MongoDB is hungry
Node.js + Postgres      ~180 MB     ~390 MB      Typical for custom backends
Node.js single-service  ~35 MB      ~160 MB      Light custom apps
Wiki (Postgres+Redis)   ~520 MB     ~1,400 MB    3-service full-stack
4-service full-stack    ~470 MB     ~1,900 MB    Postgres + 2x Node + Caddy
```

**Rule of thumb**: Budget 200-500 MB per app. UniFi is the outlier at ~1.4 GB. A 16 GB router can comfortably run 10-15 apps.
