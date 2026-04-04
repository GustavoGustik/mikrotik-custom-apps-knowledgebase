# Differences from Docker Compose

If you're familiar with Docker Compose, this guide highlights the critical differences when writing RouterOS Custom App YAML manifests.

## Quick Reference Table

| Feature | Docker Compose | RouterOS /app |
|---------|---------------|---------------|
| Service DNS | `db:5432` works | **No**. Use `127.0.0.1:5432` |
| Build support | `build: .` | **No**. Images only |
| Network isolation | Per-service possible | **Shared namespace** (all services = 1 IP) |
| Port labels | Not supported | `8080:80:web` (triggers UI URL) |
| Inline configs | External files only | `configs:` with inline `content:` |
| Placeholder vars | `${VAR}` from `.env` | `[accessIP]`, `[containerIP]`, etc. |
| Metadata | Minimal | Extensive (`descr`, `icon`, `category`, `page`) |
| Health checks | `healthcheck:` in YAML | Not in YAML (detected from Dockerfile) |
| Resource limits | `deploy.resources.limits` | Not supported |
| Secrets | `secrets:` | Not supported (use `configs:`) |
| Multiple networks | Yes | One network per app |
| Bind mounts | `./data:/app` | Named volumes only |
| `.env` files | Supported | Not supported |
| `docker-compose up` | CLI tool | `/app add ... yaml="..."` |

## 1. No Service-Name DNS Resolution

**Docker Compose**:
```yaml
services:
  backend:
    environment:
      DATABASE_URL: postgresql://user:pass@database:5432/mydb  # Works!
  database:
    image: postgres:16
```

**RouterOS** — all services share one IP via localhost:
```yaml
services:
  backend:
    environment:
      DATABASE_URL: postgresql://user:pass@127.0.0.1:5432/mydb  # Use this!
  database:
    image: docker.io/postgres:16-alpine
```

**Why**: All services in a RouterOS app share a single VETH interface and network namespace. There's no per-service DNS — everything is on the same IP.

**Note**: Hostname entries ARE injected into `/etc/hosts`, so `database:5432` technically resolves, but it points to the same IP as `localhost`. Using `127.0.0.1` is clearer and more reliable.

## 2. No Build Context

**Docker Compose**:
```yaml
services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
```

**RouterOS** — must use pre-built images:
```yaml
services:
  app:
    image: docker.io/yourusername/myapp:v1.0
```

Build images separately with `docker buildx` and push to a registry. See [Building Custom Images](09-building-custom-images.md).

## 3. Shared Network Namespace

**Docker Compose** — each service gets its own network namespace:
```
backend → 172.18.0.3:3000
database → 172.18.0.4:5432
redis → 172.18.0.5:6379
```

**RouterOS** — ALL services share ONE IP:
```
backend → 10.0.1.50:3000
database → 10.0.1.50:5432
redis → 10.0.1.50:6379
```

This means:
- **Port conflicts are possible** if two services use the same port
- Inter-service communication is always `localhost`
- Only ONE port can be exposed as `:web` for the UI URL

## 4. Port Labels

**Docker Compose** — no labels:
```yaml
ports:
  - "8080:80"
```

**RouterOS** — labels after the second colon:
```yaml
ports:
  - "8080:80:web"       # Special: triggers UI URL in WinBox
  - "8443:443:https"    # Informational label
  - "1883:1883:mqtt"    # Informational label
```

The `:web` label is special — it tells WinBox/WebFig to show a clickable URL for this app.

## 5. Inline Configuration Files

**Docker Compose** — mount external files:
```yaml
services:
  nginx:
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf
```

**RouterOS** — inline content in YAML:
```yaml
services:
  nginx:
    configs:
      - source: 'nginx_conf'
        target: '/etc/nginx/nginx.conf'
        mode: 0644

configs:
  'nginx_conf':
    content: |
      events { worker_connections 1024; }
      http {
        server {
          listen 80;
          location / { proxy_pass http://127.0.0.1:8080; }
        }
      }
```

This is actually an advantage — no need to upload separate config files.

## 6. Placeholder Variables

**Docker Compose** — environment variable substitution from `.env`:
```yaml
# .env
APP_URL=http://localhost:8080

# docker-compose.yml
environment:
  APP_URL: ${APP_URL}
```

**RouterOS** — runtime placeholders:
```yaml
environment:
  APP_URL: "[accessProto]://[accessIP]:[accessPort]"
  INTERNAL_URL: "http://[containerIP]:3000"
```

Placeholders are resolved at deployment time based on network configuration and HTTPS settings.

## 7. Volume Syntax

**Docker Compose** — bind mounts and named volumes:
```yaml
volumes:
  - ./data:/app/data          # Bind mount (host path)
  - db_data:/var/lib/postgres  # Named volume
```

**RouterOS** — named volumes only:
```yaml
volumes:
  - data:/app/data              # Named volume
  - db_data:/var/lib/postgres   # Named volume
  # No bind mounts to host filesystem!
```

Volumes stored at `<disk>/apps/<app-name>/<volume-name>/`.

## 8. Metadata

**Docker Compose** — minimal metadata:
```yaml
version: "3.8"  # That's it
```

**RouterOS** — rich metadata for catalog:
```yaml
name: myapp
descr: Description shown in UI
page: https://project.com
category: productivity
icon: https://example.com/logo.png
default-credentials: admin:password
url-path: /admin
auto-update: false
```

## 9. Restart Policies

Both support similar restart policies, but behavior differs:

**Docker Compose**:
```yaml
restart: unless-stopped
# Container restarts automatically, persists across `docker-compose up`
```

**RouterOS**:
```yaml
restart: unless-stopped
# Container restarts automatically, BUT:
# - App must be enabled for container to start on boot
# - start-on-boot=no in /container (managed by /app system)
```

## 10. depends_on

**Docker Compose** — supports health conditions:
```yaml
depends_on:
  database:
    condition: service_healthy
```

**RouterOS** — startup order only:
```yaml
depends_on:
  - database
# No conditions! Backend starts immediately after database container starts,
# NOT after database is ready to accept connections.
```

Your app must handle connection retries internally.

## Migration Checklist

When converting a `docker-compose.yml` to RouterOS YAML:

1. Remove `version:` field
2. Remove `build:` sections → use pre-built `image:`
3. Add full registry prefix to all images (`docker.io/`, `ghcr.io/`)
4. Replace service-name references with `127.0.0.1`
5. Add `:web` label to the main HTTP port
6. Convert bind mounts to named volumes
7. Convert external config files to inline `configs:`
8. Add metadata (`name`, `descr`, `category`)
9. Remove unsupported fields (`healthcheck`, `deploy`, `secrets`, `networks` per service)
10. Replace `${VAR}` with `[accessIP]` or hardcoded values
11. Add `restart: unless-stopped` to all services
