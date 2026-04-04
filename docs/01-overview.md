# Overview: MikroTik Custom Apps (RouterOS 7.22+)

## What Are Custom Apps?

Custom Apps are MikroTik's orchestration system for running containerized applications on RouterOS routers. Introduced in **RouterOS 7.22** (beta3), they provide a declarative YAML-based approach to deploy, network, and manage applications — similar to Docker Compose but designed specifically for RouterOS appliances.

## Custom Apps vs. Raw Containers

RouterOS has two levels of container management:

### Level 1: `/container` (Low-Level)
- Manual container configuration via CLI properties
- Manual VETH interface creation and bridge port assignment
- Manual firewall rules for port forwarding
- Manual environment variables via `/container/envs`
- Manual mounts via `/container/mounts`
- Shared network namespace IS possible (assign same `interface=` to multiple containers + manual `hosts=` entries) but requires manual setup of everything
- No orchestration, no lifecycle coordination, no YAML

### Level 2: `/app` (High-Level — Custom Apps)
- **Declarative YAML manifests** defining entire application stacks
- **Automatic infrastructure**: VETH creation, bridge port assignment, firewall NAT rules, reverse proxy with HTTPS, DNS domains
- **Multi-service apps**: Automatically configures multiple containers to share a single VETH (network namespace) with `hosts=` entries for service discovery — the same thing is technically possible with raw `/container`, but `/app` automates it from a single YAML file
- **Placeholder variables** for runtime configuration (`[accessIP]`, `[containerIP]`, etc.)
- **App catalog** with 110+ pre-configured apps
- **Custom app stores** via HTTP/HTTPS URLs
- **Inline config files** injected into containers at startup

## What `/app` Automatically Manages

When you enable a custom app, RouterOS automatically creates and manages:

| Resource | What Gets Created |
|----------|------------------|
| **VETH Interface** | `/interface/veth` — one per app, shared by all services |
| **Bridge Port** | `/interface/bridge/port` — attaches VETH to bridge1 or internal bridge |
| **Firewall NAT** | `/ip/firewall/nat` — dst-nat rules for port mappings (internal mode) |
| **Reverse Proxy** | `/ip/reverse-proxy` — SNI rules with Let's Encrypt certificate |
| **DNS Domain** | `<app-name>.<device-hash>.routingthecloud.com` via `/ip/cloud` |
| **Containers** | `/container` — one per service, with env vars, mounts, hosts |
| **Volumes** | `<disk>/apps/<app-name>/<volume-name>/` directories on external storage |
| **Config Files** | Inline configs written to container filesystem |

All of these are visible in the `cmds` field of `/app print detail`:

```
/app print detail where name=mosquitto
```

Output includes the `cmds=` field showing every RouterOS command that was auto-generated:

```
cmds=
  /interface set veth-app-mosquitto name=veth-app-mosquitto
  /interface bridge port add bridge=bridge1 interface=veth-app-mosquitto pvid=1
  /ip reverse-proxy add certificate=apps-*.xxx.routingthecloud.com ip-address=192.168.128.50 port=1883 sni=mosquitto.xxx.routingthecloud.com
  /container set app-mosquitto check-certificate=yes cmd="" ... name=app-mosquitto remote-image=docker.io/eclipse-mosquitto:latest ...
```

## Architecture

```
┌────────���────────────────────────────────────────────┐
│                    RouterOS 7.22+                     │
│                                                       │
│  /app (Orchestration Layer)                          │
│  ├── YAML Manifest Parser                            │
│  ├── Infrastructure Generator (VETH, NAT, proxy)     │
│  ├── Container Lifecycle Manager                     │
│  ├── App Catalog (110+ built-in apps)                │
│  └── Custom App Store Support                        │
│                                                       │
│  /container (Runtime Layer)                           │
│  ├── OCI Container Runtime                           │
│  ├── Image Pull & Layer Cache                        │
│  └── Process Isolation (cgroups, namespaces)          │
│                                                       │
│  /interface/veth ←→ /interface/bridge ←→ LAN/WAN     │
│  /ip/firewall/nat (auto-created dst-nat rules)       │
│  /ip/reverse-proxy (auto-created SNI with HTTPS)     │
│  /ip/cloud (DDNS for domain names)                   │
└─────────────────────────────────────────────────────┘
```

## Supported Hardware

Custom Apps require:

- **CPU Architecture**: ARM64 or x86 (NOT MIPS, TILE, or PowerPC)
- **RouterOS**: 7.22+ with `container.npk` package
- **External Storage**: NVMe, USB, or SD card (ext4 or btrfs) — internal flash is insufficient
- **Device Mode**: Container mode must be enabled (`/system/device-mode/update container=yes`)

### Verified Routers

| Router | Arch | RAM | Notes |
|--------|------|-----|-------|
| CCR2116-12G-4S+ | ARM64 (Cortex-A72) | 16 GB | Excellent. 10+ apps comfortably |
| CCR2216-1G-12XS-2XQ | ARM64 (Cortex-A72) | 16 GB | Same as CCR2116 |
| RB5009UG+S+ | ARM64 | 1 GB | Limited by RAM. 2-3 light apps max |
| RB5009UPr+S+ | ARM64 | 1 GB | Same as RB5009, PoE variant |
| x86 / CHR | x86_64 | Varies | Full support, most flexible |

### NOT Supported

| Router | Arch | Why |
|--------|------|-----|
| hEX (RB750Gr3) | MIPSBE | No container support |
| hAP ac2 (RBD52G) | ARM32 | Insufficient RAM/CPU |
| CCR1036 | TILE | No container support |
| RB1100AHx4 | ARM32 | No container support |

## App Catalog

RouterOS 7.22+ ships with 110+ pre-configured apps in the built-in catalog, including:

- **Networking**: Pi-hole, AdGuard Home, Caddy, Cloudflared, WireGuard UI
- **Home Automation**: Home Assistant, Zigbee2MQTT, Mosquitto, Node-RED
- **Productivity**: Nextcloud, Docmost, Gitea, Calibre-Web
- **Monitoring**: Grafana, Prometheus, Uptime Kuma
- **Media**: Jellyfin, Plex, Immich
- **Communication**: Matrix/Conduit, Cinny

You can also add **custom apps** with your own YAML manifests and create **custom app stores** served over HTTP.

## Key Terminology

| Term | Meaning |
|------|---------|
| **Custom App** | User-defined app with custom YAML manifest |
| **Catalog App** | Pre-configured app from the built-in RouterOS catalog |
| **App Store** | HTTP-served YAML array of app definitions |
| **VETH** | Virtual Ethernet interface — one per app, shared by all services |
| **Service** | A single container within an app |
| **Volume** | Persistent storage directory on external disk |
| **Inline Config** | Config file content embedded in YAML, injected into container |
| **Placeholder** | Runtime variable like `[accessIP]` replaced at deployment |
| **Internal Bridge** | Isolated 172.18.0.0/24 bridge with NAT (default mode) |
| **External Bridge** | Direct attachment to existing bridge (e.g., bridge1/LAN) |
