# MikroTik Custom Apps Knowledge Base

Complete documentation and know-how for **MikroTik RouterOS Custom Apps** (RouterOS 7.22+).

Custom Apps are NOT just containers. They are a full **orchestration system** that uses YAML manifests to automatically manage:

- Container lifecycle (pull, start, stop, restart, update)
- Network interfaces (VETH creation, bridge port assignment)
- Firewall rules (dst-nat for port forwarding)
- Reverse proxy with automatic HTTPS (Let's Encrypt via `/ip/cloud`)
- DNS domains (`<app-name>.<device>.routingthecloud.com`)
- Volume storage on external disk
- Service discovery via `/etc/hosts` injection
- Health checks and auto-restart

## What is this repo?

A comprehensive knowledge base built from:

1. **Official MikroTik documentation** for Containerized App Management
2. **Community resources** (amm0's manual, forum posts, GitHub repos)
3. **Real production deployment** on CCR2116-12G-4S+ running 10+ custom apps
4. **Hands-on experience** deploying UniFi, Zigbee2MQTT, Node-RED, custom Node.js apps, and more

## Documentation

| Document | Description |
|----------|-------------|
| [Overview](docs/01-overview.md) | What Custom Apps are and how they differ from raw `/container` |
| [Prerequisites](docs/02-prerequisites.md) | Hardware, software, and setup requirements |
| [YAML Reference](docs/03-yaml-reference.md) | Complete YAML manifest specification |
| [Networking](docs/04-networking.md) | Network modes, VETH, bridge, NAT, VLAN, service discovery |
| [Auto-Managed Infrastructure](docs/05-auto-managed-infra.md) | What `/app` creates automatically (firewall, reverse proxy, DNS) |
| [Deployment Guide](docs/06-deployment.md) | Step-by-step deployment from scratch |
| [Operations](docs/07-operations.md) | Day-to-day management, updates, backup, restore |
| [Troubleshooting](docs/08-troubleshooting.md) | Common issues and solutions |
| [Building Custom Images](docs/09-building-custom-images.md) | Building Docker images for MikroTik ARM64/x86 |
| [App Store](docs/10-app-store.md) | Creating and hosting your own app catalog |
| [Real-World Examples](docs/11-real-world-examples.md) | Production apps running on CCR2116 |
| [Differences from Docker Compose](docs/12-differences-from-docker-compose.md) | Key differences for Docker users |
| [Vibecoder & AI Guide](docs/13-vibecoder-guide.md) | Guide for AI-assisted development of custom apps |
| [Backup and Restore](docs/15-backup-and-restore.md) | Backup strategy with Proxmox, restore procedures |
| [RouterOS Changelog](docs/14-routeros-changelog.md) | Container & app feature history across RouterOS versions |

## Example YAML Manifests

### Single-Service Apps
- [`mosquitto.app.yml`](examples/single-service/mosquitto.app.yml) - MQTT broker with inline config
- [`zigbee2mqtt.app.yml`](examples/single-service/zigbee2mqtt.app.yml) - Zigbee bridge
- [`nodered.app.yml`](examples/single-service/nodered.app.yml) - Low-code automation

### Multi-Service Apps
- [`unifi.app.yml`](examples/multi-service/unifi.app.yml) - WiFi controller (MongoDB + UniFi)
- [`sia-gateway.app.yml`](examples/multi-service/sia-gateway.app.yml) - Alarm receiver (Postgres + Node.js)
- [`docmost.app.yml`](examples/multi-service/docmost.app.yml) - Wiki (Postgres + Redis + Docmost)
- [`mikrotik-controller.app.yml`](examples/multi-service/mikrotik-controller.app.yml) - Router management (4 services)

### Custom Code Apps
- [`hue-loxone-bridge.app.yml`](examples/custom-code/hue-loxone-bridge.app.yml) - Custom bridge with inline config
- [`mqtt-logger.app.yml`](examples/custom-code/mqtt-logger.app.yml) - Custom Node.js on generic image

## Quick Start

```bash
# 1. Enable container mode (requires reboot)
/system/device-mode/update container=yes

# 2. Run setup wizard
/app setup

# 3. Deploy an app
/app add disabled=no network=bridge1 yaml="
name: myapp
descr: My first custom app
services:
  web:
    image: docker.io/nginx:alpine
    ports:
      - 8080:80:web
    restart: unless-stopped
"

# 4. Check status
/app print where name=myapp
```

## Verified Hardware

| Router | Architecture | RAM | Status |
|--------|-------------|-----|--------|
| CCR2116-12G-4S+ | ARM64 (Cortex-A72) | 16 GB | Primary test platform, 10+ apps |
| RB5009UG+S+ | ARM64 | 1 GB | Tested, limited by RAM |
| x86/CHR | x86_64 | Varies | Supported |

## License

This knowledge base is released under [MIT License](LICENSE). MikroTik and RouterOS are trademarks of SIA Mikrotikls.
