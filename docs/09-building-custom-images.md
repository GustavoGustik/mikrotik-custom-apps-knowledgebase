# Building Custom Docker Images for MikroTik

How to build and deploy your own container images on MikroTik RouterOS.

## Architecture Requirements

MikroTik routers support:
- **ARM64** (aarch64) — CCR2116, CCR2216, RB5009, etc.
- **x86_64** — x86 routers, CHR

You MUST build images for the correct architecture. An x86 image will NOT run on ARM64 routers.

## Method 1: Docker Buildx (Recommended)

Build multi-architecture images with Docker Buildx:

```bash
# Create builder (one-time)
docker buildx create --use --name multiarch

# Build and push for ARM64
docker buildx build \
  --platform linux/arm64 \
  -t docker.io/yourusername/myapp:v1.0 \
  --push .

# Build for both architectures
docker buildx build \
  --platform linux/arm64,linux/amd64 \
  -t docker.io/yourusername/myapp:v1.0 \
  --push .
```

## Method 2: Podman

```bash
# Build ARM64 image
podman build --platform linux/arm64 -t myapp:v1.0 .

# Save as tar
podman save -o myapp-arm64.tar myapp:v1.0

# Upload to router
scp myapp-arm64.tar admin@10.0.1.1:/nvme1/

# Import on router
/container/add file=nvme1/myapp-arm64.tar ...
```

## Dockerfile Best Practices for MikroTik

### Keep Images Small

MikroTik routers have limited storage and bandwidth. Minimize image size:

```dockerfile
# Use Alpine-based images
FROM node:20-alpine

# Multi-stage build
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM node:20-alpine
WORKDIR /app
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
CMD ["node", "dist/index.js"]
```

### Use ARM64-Compatible Base Images

Always verify ARM64 support:

| Base Image | ARM64 | Notes |
|-----------|-------|-------|
| `node:20-alpine` | Yes | Recommended for Node.js |
| `python:3.12-alpine` | Yes | Recommended for Python |
| `golang:1.22-alpine` | Yes | Build stage only |
| `postgres:16-alpine` | Yes | Database |
| `redis:7.2-alpine` | Yes | Cache |
| `mongo:4.4.18` | Yes | **Max version for Cortex-A72** |
| `caddy:2-alpine` | Yes | Reverse proxy |
| `nginx:alpine` | Yes | Web server |
| `ubuntu:24.04` | Yes | Full OS (larger) |

### Health Check

Include a health check endpoint for RouterOS health monitoring:

```dockerfile
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
  CMD wget --spider -q http://localhost:3000/health || exit 1
```

RouterOS automatically detects and uses Docker HEALTHCHECK if defined.

## Example: Node.js Custom App

### Dockerfile

```dockerfile
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --production=false
COPY . .
RUN npm run build
RUN npm prune --production

FROM node:20-alpine
WORKDIR /app
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package.json ./

EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=10s CMD wget -q --spider http://localhost:3000/health || exit 1
CMD ["node", "dist/index.js"]
```

### Build and Push

```bash
docker buildx build --platform linux/arm64 \
  -t docker.io/yourusername/myapp:2026-04-04-r1 \
  --push .
```

### YAML Manifest

```yaml
name: myapp
descr: My custom Node.js application
category: productivity
services:
  app:
    image: docker.io/yourusername/myapp:2026-04-04-r1
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

## Alternative: Generic Image + Volume

Instead of building a custom image, use a generic base image and mount code as a volume:

```yaml
services:
  app:
    image: docker.io/node:20-alpine
    command: "node /app/dist/index.js"
    volumes:
      - app:/app
    restart: unless-stopped
```

Then upload your built code:

```bash
# Build locally
npm run build

# Upload to router
scp -r dist/ admin@10.0.1.1:/nvme1/apps/myapp/app/dist/
scp package.json admin@10.0.1.1:/nvme1/apps/myapp/app/
scp -r node_modules/ admin@10.0.1.1:/nvme1/apps/myapp/app/node_modules/
```

**Pros**: No need to build Docker images, faster iteration
**Cons**: Manual dependency management, larger volume size, no layer caching

## Registry Options

| Registry | URL Prefix | Rate Limits | Auth Required |
|----------|-----------|-------------|---------------|
| Docker Hub | `docker.io/` | 100/6h anon, 200/6h free | No (public) |
| GitHub CR | `ghcr.io/` | None for public | No (public) |
| LinuxServer | `lscr.io/` | None | No |
| Quay.io | `quay.io/` | None for public | No (public) |
| Self-hosted | Custom URL | None | Depends |

### Using GitHub Container Registry

```bash
# Login
echo $GITHUB_TOKEN | docker login ghcr.io -u USERNAME --password-stdin

# Build and push
docker buildx build --platform linux/arm64 \
  -t ghcr.io/yourusername/myapp:v1.0 \
  --push .

# Make public (optional)
# Go to GitHub → Packages → myapp → Settings → Change visibility
```

YAML:
```yaml
image: ghcr.io/yourusername/myapp:v1.0
```

## Image Tagging Strategy

Recommended tagging for production:

```
yourusername/myapp:2026-04-04-r1     # Date-based (preferred)
yourusername/myapp:v1.2.3            # Semantic versioning
yourusername/myapp:latest            # Only for dev/testing
```

**Never use `:latest` in production YAML** — it makes deployments unpredictable and can break on auto-update.
