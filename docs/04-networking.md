# Networking

Custom Apps networking is one of the most important and nuanced parts of the system. Understanding the network modes and their implications is critical for reliable deployments.

## The `network` Parameter (How Bridge Selection Works)

Every app has **two** network-related settings:

1. **`default-network`** — Comes from the YAML manifest. Determined by the `networks:` section.
2. **`network`** — CLI override on `/app add` or `/app set`. Takes precedence over YAML.

### How it's determined

| YAML `networks:` section | `default-network` value |
|--------------------------|------------------------|
| No `networks:` section | `internal` |
| `networks: default: name: lan, external: true` | `bridge1` (the LAN bridge) |

### The `network` parameter values

| `/app` `network=` value | Behavior |
|------------------------|----------|
| `default` | Use whatever `default-network` the YAML defines. This is the default for catalog apps. |
| `bridge1` | **Override**: Attach VETH directly to `bridge1` (LAN bridge). Ignores YAML `networks:` section. |
| `internal` | **Override**: Force internal isolated bridge (172.18.0.0/24 with NAT). |
| `<any-bridge-name>` | Attach to a specific bridge by name (e.g., `bridge-iot`, `bridge-guest`). |

### Real-world example from production router (91 apps)

```
/app print proplist=name,default-network,network where !disabled
```

| App | default-network (YAML) | network (CLI) | Effective Mode |
|-----|----------------------|---------------|----------------|
| docmost | internal | default | **internal** (NAT at 172.18.0.6) |
| mosquitto | internal | bridge1 | **bridge1** (LAN at 192.168.128.50) |
| zigbee2mqtt | internal | bridge1 | **bridge1** (LAN at 192.168.128.51) |
| unifi | internal | bridge1 | **bridge1** (LAN at 192.168.128.54) |

Some **catalog apps** come pre-configured with `default-network=bridge1` because they need LAN access by design:

| Catalog App | default-network | Why |
|------------|-----------------|-----|
| home-assistant | bridge1 | Needs mDNS, device discovery |
| chr (Cloud Hosted Router) | bridge1 | Needs direct network access |
| jellyfin | bridge1 | Media streaming, DLNA |
| plex | bridge1 | Media streaming, DLNA |
| syncthing | bridge1 | P2P file sync |
| transmission | bridge1 | BitTorrent, needs direct ports |
| upsnap | bridge1 | Wake-on-LAN, needs L2 |

Most other catalog apps (84 out of 91) default to `internal`.

### Setting the network mode

**At creation time**:
```
# Use YAML default (usually internal)
/app add yaml="..." 

# Override to bridge1 (LAN)
/app add network=bridge1 yaml="..."

# Force internal even if YAML says bridge1
/app add network=internal yaml="..."
```

**After creation**:
```
# Change network mode
/app/set myapp network=bridge1

# Reset to YAML default
/app/set myapp network=default
```

**Note**: Changing network mode requires disable/enable cycle to take effect.

## Network Modes in Detail

### Mode 1: Internal Bridge (Default — NAT)

When no `networks:` section is specified OR `network=default` is used with `default-network=internal`.

```
                    Internet
                       │
                  ┌────┴────┐
                  │ Router   │ 192.168.128.1
                  │ bridge1  │
                  └────┬────┘
                       │
        ┌──────────────┤ (LAN clients can access via router IP + port)
        │              │
   ┌────┴─────┐  ┌────┴──────────┐
   │ LAN      │  │ internal      │ 172.18.0.0/24
   │ devices  │  │ bridge        │ (gateway: 172.18.0.1)
   └──────────┘  │               │
                 │  ┌──────────┐ │
                 │  │ veth-app │ │ 172.18.0.x
                 │  │ (app)    │ │
                 │  └──────────┘ │
                 └───────────────┘
```

**How it works**:
- RouterOS creates an isolated `internal` bridge with subnet `172.18.0.0/24`
- Each app gets the next available IP starting at `.2`
- Port mappings become `/ip/firewall/nat` dst-nat rules
- LAN clients access apps via `<router-ip>:<host-port>`
- Outbound traffic from containers is masqueraded (NAT)
- `internal` bridge is added to `LAN` interface list

**Pros**: Isolated, secure, no IP conflicts
**Cons**: Extra NAT hop, can't be directly reached from LAN devices, more complex debugging

### Mode 2: External Bridge (Direct LAN Access)

When `networks:` specifies external bridge OR `network=bridge1` is set:

```yaml
networks:
  default:
    name: lan
    external: true
```

Or via CLI: `/app add ... network=bridge1`

```
                    Internet
                       │
                  ┌────┴────┐
                  │ Router   │ 192.168.128.1
                  │ bridge1  │
                  └────┬────┘
                       │
        ┌──────────────┼──────────────┐
        │              │              │
   ┌────┴─────┐  ┌────┴─────┐  ┌────┴──────────┐
   │ LAN      │  │ veth-app │  │ Other apps    │
   │ devices  │  │ (app)    │  │ on bridge1    │
   │          │  │ .128.50  │  │ .128.51, etc  │
   └──────────┘  └──────────┘  └───────────────┘
```

**How it works**:
- VETH interface attached directly to `bridge1`
- Container gets IP via DHCP (VETH `dhcp=yes`)
- No NAT — direct L2 access from LAN
- Container is a first-class citizen on the LAN network
- Static DHCP lease recommended for stable IP

**Pros**: Direct access, simpler networking, lower latency, better for IoT/discovery protocols
**Cons**: Container exposed to LAN, uses LAN IP space, DHCP dependency

## Choosing Network Mode

| Use Case | Recommended Mode | Why |
|----------|-----------------|-----|
| MQTT Broker (Mosquitto) | **bridge1** | IoT devices need direct access |
| Zigbee2MQTT | **bridge1** | Needs to talk to Mosquitto, Node-RED |
| Node-RED | **bridge1** | Automation hub, needs LAN access |
| UniFi Controller | **bridge1** | APs need L2 discovery (port 10001/udp) |
| Web app (Docmost, Wiki) | **internal** | Only needs HTTP, NAT is fine |
| Database-only service | **internal** | Not accessed directly from LAN |
| Security-sensitive app | **internal** | Isolated from LAN |
| Cloudflare Tunnel | **internal** | Only outbound traffic needed |

## Shared Network Namespace

**All services within one app share a single VETH interface and IP address.**

This means:
- Services communicate via `localhost` / `127.0.0.1`
- Service hostnames resolve to the shared IP (via `/etc/hosts`)
- No per-service port isolation — port conflicts between services are possible

```yaml
# In a multi-service app:
services:
  database:
    image: docker.io/postgres:16-alpine
    # Listens on :5432

  backend:
    image: docker.io/node:20-alpine
    environment:
      # Use localhost, NOT the service name:
      DATABASE_URL: postgresql://user:pass@127.0.0.1:5432/mydb
```

## Service Discovery via /etc/hosts

RouterOS injects hostname entries into each container's `/etc/hosts`. All services in an app get entries for all other services:

For a 3-service app (gateway, postgres, redis) on IP 192.168.128.15:
```
# Inside each container:
192.168.128.15 gateway
192.168.128.15 postgres
192.168.128.15 redis
```

This means you CAN use service hostnames (`postgres:5432`) but they all resolve to the same IP as `localhost`. Using `localhost` or `127.0.0.1` is more explicit and recommended.

**Exception**: For Caddy reverse proxy within the same app, using hostnames like `backend:3000` works because the `hosts` entries map to the shared IP.

## Static DHCP Leases

When using external bridge mode, containers get IP via DHCP. For stable IPs:

### 1. Find VETH MAC Address

```
/interface/veth/print where name~"app-myapp"
```

### 2. Create Static Lease

```
/ip/dhcp-server/lease/add \
  address=192.168.128.50 \
  mac-address=AA:BB:CC:DD:EE:FF \
  server=dhcp1 \
  comment="app-myapp"
```

### 3. Restart App to Pick Up New IP

```
/app disable myapp
/app enable myapp
```

### VETH MAC Change Warning

**VETH MAC addresses change when an app is deleted and recreated.** This means:
- Static DHCP leases become stale
- You must update the lease with the new MAC
- Consider using a sync script (see [scripts/sync-dhcp-lease.rsc](../scripts/sync-dhcp-lease.rsc))

## VLAN Support

Apps can be assigned to VLANs via `pvid` (Port VLAN ID):

```
# Can only be set via CLI, not in YAML
/app/set myapp pvid=10
```

This sets the VETH's PVID on the bridge, which tags traffic with VLAN ID 10 when `vlan-filtering=yes` is enabled on the bridge.

## HTTPS and Reverse Proxy

When `use-https=yes` (default for all apps):

1. RouterOS creates a reverse proxy SNI rule:
   ```
   /ip/reverse-proxy/add certificate=apps-*.xxx.routingthecloud.com \
     ip-address=<container-ip> port=<first-web-port> \
     sni=<app-name>.xxx.routingthecloud.com
   ```

2. Automatic Let's Encrypt certificate via `/ip/cloud`

3. App accessible at: `https://<app-name>.<device-hash>.routingthecloud.com`

4. Placeholder variables change when HTTPS is active:
   - `[accessIP]` → domain name instead of IP
   - `[accessPort]` → `443`
   - `[accessProto]` → `https`

**Common issue**: "reverse-proxy: bind error: cannot bind to port 443" — This appears when another service (e.g., WebFig on :443) is already using port 443. Solution: move WebFig to a different port or disable HTTPS for WebFig.

## Firewall Rules (Auto-Generated)

For **internal** mode apps with port mappings:

```
# Auto-generated by /app:
/ip/firewall/nat/add \
  action=dst-nat \
  chain=dstnat \
  comment="app docmost redirect to web" \
  dst-address=192.168.128.1 \
  dst-port=3013 \
  protocol=tcp \
  to-addresses=172.18.0.6 \
  to-ports=3000
```

For **bridge1** mode apps: No firewall rules needed (direct access).

## Inter-App Communication

Apps on the same bridge can communicate directly:

```
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│ Zigbee2MQTT  │───→│ Mosquitto    │←───│ Node-RED     │
│ .128.51      │    │ .128.50:1883 │    │ .128.52      │
└──────────────┘    └──────────────┘    └──────────────┘
         All on bridge1 — direct L2 communication
```

Configure with IPs in environment variables:
```yaml
# In zigbee2mqtt configuration:
mqtt:
  server: mqtt://192.168.128.50:1883
```

## DNS Resolution Inside Containers

Containers use the router as DNS server by default. This means:
- They can resolve external domains (internet)
- They can resolve other containers via the auto-injected `/etc/hosts`
- They cannot resolve apps by name across different apps (use IPs)
