# CLAUDE.md - Instructions for AI Assistants

This repository documents MikroTik RouterOS Custom Apps (7.22+). When helping users with this codebase:

## Key Concepts

- **Custom Apps != Containers**. The `/app` system is an orchestration layer ABOVE `/container`. It auto-manages VETH interfaces, bridge ports, firewall NAT rules, reverse proxy with HTTPS, DNS domains, and container lifecycle.
- **YAML manifests** are similar to Docker Compose but NOT identical. Key differences: no service-name DNS (use `localhost` or `127.0.0.1`), no `build:` context, inline `configs:` instead of files, runtime placeholder variables (`[accessIP]`, `[containerIP]`, etc.).
- **All services in one app share a single VETH** (one IP address, one network namespace). Inter-service communication uses `localhost`.
- **Never use `/container` commands on app-managed containers** except `stop` and `start`. Use `/app` commands for everything else.

## YAML Validation

Schema: `https://tikoci.github.io/restraml/routeros-app-yaml-schema.latest.json`

## Common Patterns

- **Single-service**: Simple app with one container (e.g., Zigbee2MQTT, Node-RED)
- **Multi-service**: App + database sharing localhost (e.g., UniFi + MongoDB, SIA Gateway + Postgres)
- **Custom code on generic image**: `node:20-alpine` with code on a volume, custom `command:` (e.g., SIA Gateway, MQTT Logger)
- **Inline configs**: Use `configs:` section for config files injected at startup (e.g., Mosquitto, Hue-Loxone Bridge)

## Architecture Constraints

- Supported: ARM64, x86. NOT supported: MIPS, TILE, PowerPC.
- MongoDB 4.4.18 is the MAX version for Cortex-A72 (CCR2116/CCR2216). 4.4.19+ crashes with "Illegal instruction".
- External storage (NVMe/USB/SD) is REQUIRED for apps. Internal flash is too small.
- No rootless containers. All run as root.

## Network Modes

- **bridge1 (LAN)**: Direct access, DHCP for IP, needs static DHCP lease for stable IP
- **internal**: NAT behind router IP, auto dst-nat rules, isolated from LAN

## When Writing YAML

1. Always specify full registry: `docker.io/`, `ghcr.io/`, `lscr.io/`
2. Use `:web` label on the port you want shown in WinBox UI
3. Use `127.0.0.1` not service names for inter-service DB connections
4. Pin image tags in production (never `:latest`)
5. Use `restart: unless-stopped` for persistence across reboots

## When Deploying

- **Always deploy via CLI**: `/app add disabled=yes network=bridge1 yaml="<yaml>"` — this sets the `c` (CUSTOM) flag
- **Always verify `c` flag after creation**: `/app print where name=myapp` must show `c`
- Without the `c` flag, the custom app is indistinguishable from 90+ built-in catalog apps in WinBox, causing confusion during maintenance
