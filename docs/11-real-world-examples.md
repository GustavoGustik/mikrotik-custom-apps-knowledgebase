# Real-World Examples

Production apps running on CCR2116-12G-4S+ (ARM64, 16 GB RAM, RouterOS 7.22.1, NVMe storage).

## Overview

| # | App | Services | Network | IP | Memory | Purpose |
|---|-----|----------|---------|-----|--------|---------|
| 1 | mosquitto | 1 | bridge1 | .128.50 | 13 MB | MQTT broker |
| 2 | zigbee2mqtt | 1 | bridge1 | .128.51 | 100 MB | Zigbee bridge |
| 3 | nodered | 1 | bridge1 | .128.52 | 187 MB | Automation |
| 4 | unifi | 2 | bridge1 | .128.54 | 1414 MB | WiFi controller |
| 5 | sia-gateway | 2 | bridge1 | .128.15 | 180 MB | Alarm receiver |
| 6 | hue-loxone-bridge | 1 | bridge1 | .128.16 | 30 MB | Smart home bridge |
| 7 | mqtt-logger | 1 | bridge1 | .128.55 | 37 MB | MQTT analytics |
| 8 | mikrotik-controller | 4 | bridge1 | .128.100 | 472 MB | Router management |
| 9 | docmost | 3 | internal | 172.18.0.6 | 518 MB | Wiki/docs |
| **Total** | | **17 containers** | | | **~2.9 GB** | |

## 1. Mosquitto — MQTT Broker with Inline Config

The simplest app pattern: single service with inline configuration file.

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

**Key pattern**: Inline `configs:` section replaces the need to manually upload configuration files.

## 2. Zigbee2MQTT — Single-Service with External Dependencies

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

**Key pattern**: Depends on Mosquitto (separate app), configured after first start via onboarding wizard at `http://<ip>:8080`.

## 3. UniFi — Multi-Service with Database

Two services (MongoDB + UniFi) sharing one VETH/IP.

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

**Critical**: `mongo:4.4.18` is the MAX version for Cortex-A72 (CCR2116). `MONGO_HOST: 127.0.0.1` because services share localhost.

## 4. SIA Gateway — Custom Node.js App with PostgreSQL

Custom alarm receiver using generic `node:20-alpine` image with code on volume.

```yaml
name: sia-gateway
descr: SIA DC-09 alarm receiver with MQTT, Loxone and web UI
page: https://www.securityindustry.org/industry-standards/dc-09/
category: security
default-credentials: none
url-path: /
services:
  postgres:
    image: docker.io/postgres:16-alpine
    environment:
      POSTGRES_DB: sia_gateway
      POSTGRES_USER: sia
      POSTGRES_PASSWORD: sia
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

**Key pattern**: Generic base image (`node:20-alpine`) + custom `command:` + code deployed to volume via SCP.

## 5. Hue-Loxone Bridge — Custom App with Inline JSON Config

Custom bridge between Philips Hue and Loxone Miniserver with embedded configuration.

```yaml
name: hue-loxone-bridge
descr: Bidirectional bridge between Philips Hue and Loxone Miniserver
page: https://github.com/gustavogustik/hue-loxone-bridge
category: home-automation
default-credentials: none
url-path: /
auto-update: false
services:
  bridge:
    image: docker.io/gustavogustik/hue-loxone-bridge:latest
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
          "bridgeIP": "192.168.11.7",
          "appKey": "your-hue-api-key"
        },
        "loxone": {
          "host": "192.168.11.160",
          "port": 80,
          "user": "admin",
          "password": "password"
        },
        "mappings": [
          { "name": "Kitchen", "hueId": "xxx", "loxoneUuid": "yyy" }
        ]
      }
volumes:
  data: {}
```

**Key pattern**: Custom Docker image + inline JSON config with `target_volume` and `target_path`.

## 6. MikroTik Controller — Complex 4-Service App

Centralized router management with Postgres, Node.js backend, background worker, and Caddy reverse proxy.

```yaml
name: mikrotik-controller
descr: MikroTik Controller - Centralized router management and monitoring platform
page: https://github.com/gustavo/mikrotik-controller
icon: https://upload.wikimedia.org/wikipedia/commons/7/7e/MikroTik_logo.svg
category: networking
default-credentials: admin / admin (change immediately!)
url-path: /
auto-update: false

services:
  database:
    image: docker.io/library/postgres:16.7-alpine
    container_name: mtk-database
    hostname: postgres
    environment:
      POSTGRES_DB: mikrotik_controller
      POSTGRES_USER: mikrotik
      POSTGRES_PASSWORD: MikroTik2024Secure!
      POSTGRES_INITDB_ARGS: --encoding=UTF8 --locale=C
      PGDATA: /var/lib/postgresql/data/pgdata
      TZ: Europe/Prague
    volumes:
      - pg_data:/var/lib/postgresql/data
    shm_size: "256mb"
    stop_grace_period: "30s"
    restart: unless-stopped

  backend:
    image: docker.io/gustavogustik/mikrotik-controller-backend:latest
    container_name: mtk-backend
    hostname: backend
    depends_on:
      - database
    environment:
      NODE_ENV: production
      DATABASE_URL: postgresql://mikrotik:MikroTik2024Secure!@localhost:5432/mikrotik_controller
      JWT_SECRET: SuperSecretJWTKey_Change_This_In_Production_123
      JWT_EXPIRES_IN: 7d
      PORT: "3000"
      CORS_ORIGIN: "*"
      LOG_LEVEL: info
      TZ: Europe/Prague
    stop_grace_period: "10s"
    restart: unless-stopped

  worker:
    image: docker.io/gustavogustik/mikrotik-controller-backend:latest
    container_name: mtk-worker
    hostname: worker
    depends_on:
      - database
      - backend
    environment:
      NODE_ENV: production
      DATABASE_URL: postgresql://mikrotik:MikroTik2024Secure!@localhost:5432/mikrotik_controller
      WORKER_MODE: "true"
      MONITORING_INTERVAL: "30000"
      LOG_LEVEL: info
      TZ: Europe/Prague
    command: "node dist/workers/monitoring-worker.js"
    stop_grace_period: "10s"
    restart: unless-stopped

  caddy:
    image: docker.io/library/caddy:2-alpine
    container_name: mtk-caddy
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

**Key patterns**:
- 4 services sharing single VETH/IP
- Caddy as reverse proxy (single entry point on port 80)
- Worker reuses backend image with different `command:`
- `depends_on` chains: database → backend → worker, backend → caddy
- `DATABASE_URL` uses `localhost` (not `postgres` hostname)

## 7. Docmost — App Store App (Internal Network)

Multi-service wiki running on internal bridge with NAT.

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

**Key pattern**: Uses `[accessProto]://[accessIP]:[accessPort]` placeholder for dynamic URL. Running on internal bridge (172.18.0.6) with NAT to router port 3013.

## Memory and Disk Usage Summary

```
App                     Memory      App Size    Data Size
─────────────────────────────────────────────────────────
mosquitto               13 MB       23 MB       -
zigbee2mqtt             100 MB      139 MB      7 MB
nodered                 187 MB      607 MB      51 MB
unifi                   1,414 MB    961 MB      553 MB
sia-gateway             180 MB      389 MB      119 MB
hue-loxone-bridge       30 MB       134 MB      -
mqtt-logger             37 MB       160 MB      12 MB
mikrotik-controller     472 MB      1,919 MB    283 MB
docmost                 518 MB      1,365 MB    48 MB
─────────────────────────────────────────────────────────
TOTAL                   ~2.9 GB     ~5.7 GB     ~1.1 GB
```

Router total container memory: 4,334 MB (out of 16 GB available).
