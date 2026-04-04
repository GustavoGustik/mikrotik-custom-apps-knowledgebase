# Auto-Managed Infrastructure

This is what makes Custom Apps special compared to raw `/container` usage. When you enable an app, RouterOS automatically generates and executes a series of commands to create all the supporting infrastructure.

## What Gets Auto-Created

### 1. VETH Interface

One virtual ethernet interface per app:

```
/interface/veth add name=veth-app-<appname>
```

- All services in the app share this single VETH
- VETH gets IP via DHCP (bridge1) or static assignment (internal bridge)
- VETH name format: `veth-app-<appname>` (truncated to ~16 chars)

### 2. Bridge Port

VETH attached to the appropriate bridge:

```
# For bridge1 mode:
/interface/bridge/port add bridge=bridge1 interface=veth-app-<appname> pvid=1

# For internal mode:
/interface/bridge/port add bridge=internal interface=veth-app-<appname> pvid=1
```

### 3. Reverse Proxy (HTTPS)

When `use-https=yes` (default):

```
/ip/reverse-proxy/add \
  certificate=apps-*.xxx.routingthecloud.com \
  ip-address=<container-ip> \
  port=<first-web-port> \
  sni=<appname>.xxx.routingthecloud.com
```

This creates:
- SNI-based routing to the container
- Automatic Let's Encrypt wildcard certificate
- HTTPS access at `https://<appname>.<device-hash>.routingthecloud.com`

### 4. Firewall NAT Rules (Internal Mode Only)

For each port mapping in the YAML:

```
/ip/firewall/nat/add \
  action=dst-nat \
  chain=dstnat \
  comment="app <appname> redirect to <label>" \
  dst-address=<router-ip> \
  dst-port=<host-port> \
  protocol=tcp \
  to-addresses=<container-ip> \
  to-ports=<container-port>
```

Example for Docmost (internal mode, port 3013→3000):
```
/ip/firewall/nat/add action=dst-nat chain=dstnat \
  comment="app docmost redirect to web" \
  dst-address=10.0.1.1 dst-port=3013 \
  protocol=tcp to-addresses=172.18.0.6 to-ports=3000
```

### 5. Container Configuration

For each service in the app:

```
/container/set app-<appname>-<service> \
  check-certificate=yes \
  cmd="<command>" \
  env="KEY1=val1,KEY2=val2" \
  hosts=service1:<ip>,service2:<ip> \
  layer-dir=<disk>/apps/layers \
  mount=<disk>/apps/<appname>/<vol>:/path:rw \
  name=app-<appname>-<service> \
  remote-image=<image> \
  root-dir=<disk>/apps/<appname>/<service>_root \
  start-on-boot=no \
  stop-time=30s
```

Key details:
- Container names: `app-<appname>-<service>` (or `app-<appname>` for single-service)
- Hosts: All services in the app are listed with the shared IP
- Layers shared across apps: `<disk>/apps/layers`
- Root dir per service: `<disk>/apps/<appname>/<service>_root`

### 6. Volume Directories

Created on the external disk:
```
<disk>/apps/<appname>/<volume-name>/
```

### 7. Config Files

Inline configs are written to the container filesystem as read-only mounts.

## Viewing Auto-Generated Commands

The `cmds` field in `/app print detail` shows all auto-generated commands:

```
/app print detail where name=mosquitto
```

Look for the `cmds=` field:

```
cmds=
  /interface set veth-app-mosquitto name=veth-app-mosquitto
  /interface bridge port add bridge=bridge1 interface=veth-app-mosquitto pvid=1
  /ip reverse-proxy add certificate=apps-*.xxx.routingthecloud.com ip-address=10.0.1.50 port=1883 sni=mosquitto.xxx.routingthecloud.com
  /container set app-mosquitto check-certificate=yes cmd="" ... name=app-mosquitto remote-image=docker.io/eclipse-mosquitto:latest ...
```

## Viewing Runtime Variables

The `variables-to-use-in-environment` field shows resolved placeholder values:

```
variables-to-use-in-environment=
  [containerIP]=10.0.1.50
  [containerInterface]=veth-app-mosqui
  [routerIP]=10.0.1.1
  [accessIP]=mosquitto.xxx.routingthecloud.com
  [accessPort]=443
  [accessProto]=https
```

## Infrastructure Lifecycle

### On `/app enable`:
1. Create VETH interface
2. Add bridge port
3. Create reverse proxy rule (if HTTPS)
4. Create firewall NAT rules (if internal mode)
5. Configure containers (env, mounts, hosts)
6. Pull images (if not cached)
7. Start containers in dependency order

### On `/app disable`:
1. Stop all containers
2. Remove reverse proxy rule
3. Remove firewall NAT rules
4. Remove bridge port
5. Remove VETH interface
6. Container and volume data preserved

### On `/app remove` (after disable):
1. Remove app definition from `/app`
2. Container images remain in layer cache
3. Volume data remains on disk

### On `/app cleanup`:
1. **DESTROYS ALL DATA** — removes volumes, configs, root dirs
2. Removes cached layers if unused by other apps
3. **IRREVERSIBLE** — backup volumes first!

## Auto-Update Mechanism

When `auto-update=yes`:
- RouterOS periodically checks for new image tags
- Downloads and replaces container images
- Restarts affected containers
- Manual edits to dynamic config are overridden

**Warning**: Auto-update with `:latest` tags can cause unexpected upgrades. Use fixed tags if stability is critical.

## Interaction Between /app and /container

**Golden rule**: Never use `/container` commands on app-managed containers except `stop` and `start`.

| Command | Safe? | Use Instead |
|---------|-------|-------------|
| `/container/stop` | **Yes** | — |
| `/container/start` | **Yes** | — |
| `/container/shell` | **Yes** | — |
| `/container/remove` | **NO** | `/app disable` then `/app remove` |
| `/container/set` | **NO** | Edit YAML, recreate app |
| `/container/add` | **NO** | Use `/app add` |

Using `/container/remove` or `/container/set` on app-managed containers **desynchronizes the /app system**, causing app definitions to disappear on reboot while orphaned containers remain.
