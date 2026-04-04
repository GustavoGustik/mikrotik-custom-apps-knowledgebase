# YAML Manifest Reference

The YAML manifest is the core of every custom app. It defines services, networking, volumes, configuration files, and metadata.

## Complete Structure

```yaml
# Metadata (displayed in WinBox/WebFig app catalog)
name: my-app                          # REQUIRED. Lowercase, hyphens OK
descr: Short description of the app   # REQUIRED. 50-150 chars
page: https://example.com             # Project homepage URL
category: productivity                # Organization category
icon: https://example.com/logo.png    # App icon URL
default-credentials: admin:password   # Shown in UI for first login
url-path: /admin                      # Path suffix for web access URL
auto-update: false                    # Enable automatic image updates

# Services (one or more containers)
services:
  service-name:
    image: docker.io/org/image:tag    # REQUIRED. Always include registry
    container_name: my-container      # Explicit container identifier
    hostname: myhost                  # Container hostname
    ports:
      - "8080:80:web"                 # host:container:label
    environment:
      KEY: value                      # Environment variables
    volumes:
      - data:/app/data                # Named volume mounts
    command: "node server.js"         # Override CMD
    configs:
      - source: 'config_name'        # Inject config file
        target: '/etc/app/config.yml'
        mode: 0644
    depends_on:
      - other-service                 # Startup order
    restart: unless-stopped           # Restart policy
    user: "1000:1000"                 # Run as UID:GID
    shm_size: "256mb"                 # Shared memory
    stop_grace_period: "30s"          # Shutdown timeout

# Inline configuration files
configs:
  'config_name':
    content: |
      config file content here
      supports multiline YAML strings

# Volume declarations
volumes:
  data: {}

# Network configuration (optional)
networks:
  default:
    name: lan
    external: true
```

## Root-Level Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | **Yes** | Unique lowercase identifier. Used for container names (`app-<name>`), VETH names (`veth-app-<name>`), and DNS domains |
| `descr` | string | **Yes** | Brief description shown in WinBox/WebFig |
| `page` | URL | No | Project homepage link |
| `category` | string | No | Category for UI grouping (productivity, networking, monitoring, home-automation, media, communication, security, development, storage, games) |
| `icon` | URL | No | Application logo/icon URL |
| `default-credentials` | string | No | Initial login credentials shown in UI |
| `url-path` | string | No | Path suffix appended to access URL (e.g., `/admin`) |
| `auto-update` | boolean | No | Auto-pull latest images periodically |

## Service Fields

### `image` (Required)

Container image with explicit registry:

```yaml
image: docker.io/postgres:16-alpine        # Docker Hub official
image: docker.io/nodered/node-red:latest    # Docker Hub org
image: ghcr.io/koenkk/zigbee2mqtt:latest    # GitHub Container Registry
image: lscr.io/linuxserver/unifi-network-application:latest  # LinuxServer.io
image: docker.io/gustavogustik/myapp:v1.0   # Custom image
```

**Best practice**: Always specify full registry prefix. Without it, the default from `/container/config` is used (typically `docker.io`).

### `ports`

Format: `"host_port:container_port[:label]"` or `"host_port:container_port/protocol[:label]"`

```yaml
ports:
  - "8080:80:web"           # TCP (default), labeled "web" for UI
  - "8443:443/tcp:https"    # Explicit TCP
  - "53:53/udp:dns"         # UDP
  - "1883:1883:mqtt"        # Custom label
  - "3000:3000"             # No label
```

**Labels**:
- The `:web` label is special — it triggers the UI URL display in WinBox/WebFig
- Other labels are informational and appear in `/app print`

**Port mapping behavior**:
- **Internal network (default)**: Creates `/ip/firewall/nat` dst-nat rule from `router-ip:host_port` to `container-ip:container_port`
- **External bridge (bridge1)**: No NAT needed — container gets its own IP on the LAN

### `environment`

Two syntaxes supported:

```yaml
# Object syntax (recommended)
environment:
  POSTGRES_DB: mydb
  POSTGRES_USER: user
  POSTGRES_PASSWORD: pass
  TZ: Europe/Prague

# Array syntax
environment:
  - PUID=1000
  - PGID=1000
```

### `volumes`

Format: `"volume_name:/container/path"` or `"prefix/subdir:/container/path"`

```yaml
volumes:
  - data:/app/data                              # Simple volume
  - db_data:/var/lib/postgresql/data            # Database storage
  - wordpress/html:/var/www/html                # Prefixed (creates wordpress-html dir)
  - caddy/conf:/etc/caddy                       # Prefixed
```

**Storage paths**: Volumes are stored at `<disk>/apps/<app-name>/<volume-name>/`

Subdirectory notation (`prefix/subdir`) is flattened with hyphens:
- `wordpress/html` → `<disk>/apps/myapp/wordpress-html/`

**Important**: No bind mounts to host directories. Only named volume notation.

### `command`

Override the container's default CMD:

```yaml
# String format
command: "node /app/dist/index.js"

# Complex commands
command: "sh -c 'npm run migrate && node server.js'"

# Shell with entrypoint script
command: "sh /app/entrypoint.sh"
```

### `configs`

Reference inline config files from the top-level `configs:` section:

```yaml
services:
  app:
    configs:
      - source: 'app_config'           # Must match key in configs:
        target: '/etc/app/config.yaml'  # Path inside container
        mode: 0644                      # File permissions (octal)
```

### `depends_on`

Controls startup order (not health-check conditions):

```yaml
services:
  backend:
    depends_on:
      - database
      - redis
  database:
    image: docker.io/postgres:16-alpine
  redis:
    image: docker.io/redis:7.2-alpine
```

**Important**: This only controls order. There is no `condition: service_healthy` like in Docker Compose. The dependent service starts immediately after the dependency container starts, NOT after it's healthy.

### `restart`

```yaml
restart: unless-stopped   # Restart always except when manually stopped (recommended)
restart: always           # Restart always
restart: no               # Never restart
restart: on-failure       # Restart only on non-zero exit
```

### Other Service Fields

| Field | Type | Example | Description |
|-------|------|---------|-------------|
| `container_name` | string | `mtk-backend` | Custom container name (informational) |
| `hostname` | string | `postgres` | Container hostname |
| `user` | string | `"1000:1000"` or `"0:0"` | Run as specific UID:GID |
| `shm_size` | string | `"256mb"` | Shared memory size (important for PostgreSQL) |
| `stop_grace_period` | string | `"30s"` | Graceful shutdown timeout |
| `security_opt` | array | — | Security options |

## Configs Section

Inline configuration files injected into containers:

```yaml
configs:
  'mosquitto_conf':
    content: |
      listener 1883
      allow_anonymous true
      
      listener 9001
      protocol websockets
      allow_anonymous true

  'init_script':
    content: |
      #!/bin/bash
      echo "Initializing..."
      php artisan migrate --force

  'nginx_config':
    content: |
      events { worker_connections 1024; }
      http {
        server {
          listen 80;
          location / { proxy_pass http://127.0.0.1:8080; }
        }
      }
```

Reference in services with the `configs:` array (see above).

**Config with target volume** (alternative syntax seen in some apps):
```yaml
configs:
  'config_json':
    target_volume: data
    target_path: 'config.json'
    content: |
      { "key": "value" }
```

## Volumes Section

Declare named volumes:

```yaml
volumes:
  data: {}
  db_data: {}
  redis_data: {}
```

Volumes are created automatically at `<disk>/apps/<app-name>/<volume-name>/` when the app is enabled.

## Networks Section

### Default (Internal Bridge with NAT)

When no `networks:` section is specified:
- Creates isolated `internal` bridge (172.18.0.0/24)
- Single VETH per app
- Port mappings become dst-nat firewall rules
- NAT masquerade for outbound traffic

### External Bridge (Direct LAN Access)

```yaml
networks:
  default:
    name: lan
    external: true
```

- Attaches VETH directly to the configured `lan-bridge` (typically `bridge1`)
- Container gets IP via DHCP
- No NAT — direct network access from LAN
- Static DHCP lease recommended for stable IP

**Note**: Can also be overridden at deployment with `/app add ... network=bridge1`

## Placeholder Variables

RouterOS replaces these at runtime in environment values:

| Variable | Description | Example Value |
|----------|-------------|---------------|
| `[accessIP]` | Access IP/domain (depends on HTTPS setting) | `10.0.1.1` or `myapp.xxx.routingthecloud.com` |
| `[accessPort]` | Access port (first port with `:web` label) | `8080` or `443` (HTTPS) |
| `[accessProto]` | Protocol | `http` or `https` |
| `[containerIP]` | Container's actual IP address | `10.0.1.50` or `172.18.0.4` |
| `[containerInterface]` | VETH interface name | `veth-app-myapp` |
| `[routerIP]` | Router's configured IP | `10.0.1.1` |

**Usage**:
```yaml
environment:
  APP_URL: "[accessProto]://[accessIP]:[accessPort]"
  TRUSTED_DOMAINS: "[accessIP]"
  PUBLIC_URL: "http://[accessIP]:8016"
  CSRF_ORIGINS: "http://[accessIP]:8016,http://[accessIP]:8015"
```

## Complete Real-World Example

```yaml
name: mikrotik-controller
descr: MikroTik Controller - Centralized router management
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
      PORT: "3000"
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

## YAML Validation

### VS Code Schema

Add to your VS Code `settings.json`:

```json
{
  "yaml.schemas": {
    "https://tikoci.github.io/restraml/routeros-app-yaml-schema.latest.json": [
      "*.app.yml",
      "*.app.yaml"
    ]
  }
}
```

Or add to the YAML file header:

```yaml
# yaml-language-server: $schema=https://tikoci.github.io/restraml/routeros-app-yaml-schema.latest.json
name: myapp
```

## Unsupported Docker Compose Features

These Docker Compose fields are **NOT supported** in RouterOS YAML:

- `version` — not used
- `build` — no local builds, images only
- `.env` file references
- `secrets` — use `configs:` instead
- `healthcheck` — not supported in YAML (but some images have built-in health checks that RouterOS detects)
- `deploy`, `replicas`, `resources` — no resource limits in YAML
- `extra_hosts` — service hosts are auto-generated
- `ulimits`, `tmpfs`, `cap_add/cap_drop`
- `profiles`
- Multiple networks per service
- External volume declarations
