# RouterOS Changelog: Container & App Features

Complete history of container, `/app`, VETH, and reverse-proxy features across RouterOS versions. Extracted from official MikroTik changelogs. Includes beta/RC versions to show development direction.

---

## 7.23beta2 (Testing) — Major Container Upgrades Coming

**This beta shows where MikroTik is heading.** Many of our documented limitations are being addressed.

### /app system — significant improvements
- **`app` — allow updating YAML for existing custom app** (forces cleanup) — currently you must delete and recreate!
- **`app` — allow updating name parameter from YAML for custom apps**
- `app` — added possibility to set app command-line parameter from CLI
- `app` — allow apps on xfs file system (not just ext4/btrfs)
- `app` — allow overriding default stop signal
- **`app` — allow parsing DNS in YAML** — new YAML capability
- `app` — allow passing stop signal from YAML and passing it to container as default
- **`app` — apps now check for port availability** — apps will not start on "internal" if app masks existing service
- `app` — automatically pass any required devices to container (e.g., otbr zigbee)
- `app` — fixed saving custom apps
- **`app` — fixed YAML not exported for custom apps** — export was broken
- `app` — improved app networks and port behavior
- `app` — improved YAML error message
- `app` — stability fixes for the "/app" menu

### New catalog apps
- `app` — added **docker-with-dockge, docker-with-komodo, docker-with-portainer** — Docker-in-container with orchestration UIs!
- `app` — added HA-otbr-matter, odoo, otbr, stalwart apps

### Container engine — restart policies and OOM detection
- **`container` — added restart-policy=no/always/on-failure** — proper restart policies!
- **`container` — added stop-on-unhealthy** — auto-stop unhealthy containers
- **`container` — added restart-count, restart-interval, restart-max-count** — fine-grained restart control
- `container` — allow disabling individual container environment variables without deleting them
- `container` — allow picking mount source directories with the file picker in WinBox
- **`container` — allow setting memory-max global and per container** — hard memory limits!
- `container` — allow user-defined mounts overriding /sys and /dev
- `container` — clean up layers of non-existing containers
- **`container` — detect and show containers killed by out-of-memory killer** — OOM visibility
- `container` — fixed container entrypoint and shell override by user
- `container` — fixed losing container after reboot
- `container` — improved running container instance memory usage
- `container` — layers are now accessible under "Layers" tab
- `smb` — do not start /ip smb server on container interfaces

### What this means for custom apps

Several of our documented limitations are being fixed:

| Current Limitation (7.22) | Fix in 7.23beta2 |
|--------------------------|------------------|
| Can't edit YAML in-place (must delete/recreate) | `allow updating YAML for existing custom app` |
| No restart policies in YAML | `restart-policy=no/always/on-failure` |
| No memory hard limits | `memory-max global and per container` |
| No OOM visibility | `detect and show containers killed by OOM` |
| YAML export broken for custom apps | `fixed YAML not exported for custom apps` |
| No DNS in YAML | `allow parsing DNS in YAML` |
| No port conflict detection | `apps check for port availability` |
| Docker/Portainer not available | `docker-with-portainer/dockge/komodo` apps |

---

## 7.22.1 (2026-03-23) — Current Stable

Bug fixes only, no app/container changes relevant to custom apps.

- `defconf` — fixed architecture detection for apps

## 7.22 (2026-03-09) — Custom Apps Go Stable

**This is the release where `/app` and custom apps became stable.** Major additions:

### /app system
- **`app` — added support for custom apps** (the core feature)
- **`app` — added configurable app-store URL for custom apps**
- `app` — added health check for apps, which automatically rewrites the composed YAML
- `app` — added jupyter-notebook, livebook, myip, and rustfs apps
- `app` — allow configuring bridge port pvid for app
- `app` — enable swap on all devices that use apps to help with performance
- `app` — fixed /app/export
- `app` — fixed apps constantly polling the cloud
- `app` — fixed elasticsearch, element, pmacct-netflow apps failing to start
- `app` — fixed issue with Cinny not being able to create a root-dir
- `app` — fixed missing reverse-proxy URL
- `app` — fixed potential port collisions between apps
- `app` — show app URL only when it is running
- `app` — show DNS URL for app only if it has a reverse-proxy
- `app` — changed ui-url parameter for Smokeping and Nextcloud
- `app` — clean the backup directory after container repull
- `app` — do not show duplicate entries of required-mounts

### Container engine
- `container` — added support for zstd extraction
- `container` — automatically stop/repull/start the container on repull or remote-image change
- `container` — fixed issue where the container may not start after upgrading if root-dir was not set
- `container` — improved error message if container fails to start
- `container` — internal stability improvements
- `container` — use the user-defined envs and envlist for container shell command

### Reverse proxy
- **`ip` — added reverse-proxy** (new feature)
- `ip` — added error messages to reverse-proxy rules

## 7.21 (2026-01-12) — /app Menu Introduced (Beta)

**First appearance of the `/app` system** and massive VETH improvements:

### /app system (first appearance)
- **`container` — added "/app" menu for simple containerized app installation** (requires "container" package and enabled "container" device-mode)
- `container` — shows app URL and "running" status only when port is open
- `container` — allow app network to be any bridge interface

### Container engine
- `container` — added CPU usage monitoring
- `container` — added `hosts` setting (enables shared namespace `/etc/hosts` injection)
- `container` — added kill command to send signals (CLI only)
- `container` — added option to limit CPUs used by containers
- `container` — added root dir size display
- `container` — added run command to allow interactive mode (CLI only)
- `container` — added stop-time setting
- `container` — added update command (CLI only)
- `container` — allow /tmp tmpfs to be unlimited in size
- `container` — allow to configure extra ENV variables directly in container
- `container` — allow to disable/enable envs and mounts
- `container` — allow to specify mounts directly in container
- `container` — calculate volume sizes
- `container` — convert container mounts setting to mountlists
- `container` — do not allow layer-dir to be within some containers root-dir
- `container` — enable relevant kernel features to support more container apps
- `container` — fixed error for starting container which consists of large number of layers
- `container` — fixed extract issues
- `container` — fixed VETH when using long interface name
- `container` — general container service stability fixes and improvements
- `container` — have per container layer-dir setting
- `container` — made it possible to set timeout on /container/shell
- `container` — make sure a working directory is created if it does not exist
- `container` — show detailed import status
- `container` — show image-id field (CLI only)
- `container` — store image import data (allows keeping container after netinstall)

### VETH
- **`veth` — add container-mac-address setting**
- **`veth` — added dhcp setting** that allows to auto-configure IPv4 address (works when VETH is bridged with DHCP server)
- `veth` — added default print brief table mode
- `veth` — complain immediately when VETH gateway not reachable
- `veth` — fixed IP address not appearing in the app menu when VETH uses DHCP
- `veth` — fixed VETH interface not getting an IP address in a vlan-aware bridge with multiple DHCP servers
- `veth` — show only when container package installed
- `dhcpv4-server` — allow creating static DHCPv4 leases for VETH interfaces

### Other
- `ip-service` — do not duplicate entries for containers running in same netns
- `usb` — support video capture devices for arm64 and x86, for passthrough to containers
- `webfig` — fixed container config memory high input

## 7.20 (2025-11-03) — Container Maturation

Major container improvements, no `/app` yet:

- `container` — added "device" option to pass hardware devices to containers
- `container` — added /container/log menu, keep 100 messages per container
- `container` — added default print brief mode
- `container` — added initial support for container-in-container setups
- `container` — added option to execute commands inside container using "/container/shell cmd= user="
- `container` — added per-container memory limiting and monitoring
- `container` — added repull command
- `container` — added SCTP support
- `container` — added support for cpuset, cpu, memory, pids cgroups
- `container` — allow picking passthrough devices by descriptive name
- `container` — allow read-only mounts
- `container` — allow to mount individual files, not just directories
- `container` — allow to specify multiple envlists
- **`container` — allow to use multiple veths in a container** (enables shared network namespace manually)
- `container` — can use KVM (x86 and arm64) in container QEMU for faster virtualization
- `container` — display any error prominently in WinBox
- `container` — do not allow multiple containers with same root directory
- `container` — enable check-certificate by default for new remote imports
- `container` — improved compatibility when running containers with custom "cmd" and "entrypoint" commands
- `container` — improved error and log messages
- `container` — prevent user from setting "root-dir=/" for a container
- `container` — show a more descriptive error when tar extraction fails
- `container` — show config.json to user
- `container` — show explicit stopped flag for container
- `container` — stability improvements
- `container` — support for direct access to hardware devices
- `container` — terminate containers on shutdown, allow them to clean up properly
- **`veth` — added dhcp=yes/no property** for easy LAN container setup
- `veth` — added mac-address property
- `veth` — make veth interface MAC address stable in both RouterOS and container (+1 increment)
- `bth` — added extra file-share functionality for use with apps

## 7.19 (2025-08-04)

Minimal container changes:

- `container` — allow changing container name
- `container` — fixed repository name handling to prevent redirect issues with basic authentication
- `container` — try to derive a user readable container name from remote image or file

## 7.18 (2025-05-22)

Registry and image handling improvements:

- `container` — add default registry-url=https://lscr.io
- `container` — allow HTTP redirects when accessing container registry
- `container` — allow specifying registry using remote-image property
- `container` — improved image arch choice
- `container` — use parent directory of container root-dir for unpack by default

## 7.17 (2025-02-05)

Shell and stability improvements:

- `container` — allow import from .tar.gz file
- `container` — do not log start, end events unless logging is enabled
- `container` — fixed user and group ID range
- `container` — improved "start-on-boot" stability
- `container` — improved container shell
- `disk` — added support for SWAP (when container package is installed)

## 7.16 (2024-11-13)

- `container` — clear VETH address on container exit and mark interface as running only when VETH is in use

## Feature Timeline Summary

| Version | Date | Key Milestone |
|---------|------|---------------|
| 7.16 | 2024-11 | Basic VETH improvements |
| 7.17 | 2025-02 | SWAP support, tar.gz import |
| 7.18 | 2025-05 | Registry improvements, default lscr.io |
| 7.19 | 2025-08 | Container naming |
| 7.20 | 2025-11 | **Major**: cgroups, multi-veth, device passthrough, /container/log, memory limits, VETH DHCP |
| 7.21 | 2026-01 | **`/app` menu introduced**, hosts setting, VETH DHCP improvements, app catalog |
| 7.22 | 2026-03 | **Custom apps go stable**, reverse-proxy, app-store URLs, health checks, zstd |
| 7.22.1 | 2026-03 | Bug fixes |
| **7.23beta2** | Testing | **YAML in-place edit, restart policies, memory-max, OOM detection, Portainer/Dockge** |

## Development Direction (from 7.23 betas)

Based on the beta changelogs, MikroTik is actively investing in containers/apps. Key directions:

### 1. Moving Toward Full Docker Compose Parity
- Restart policies (`no/always/on-failure`), health-based stop, restart limits
- Memory hard limits (`memory-max`)
- DNS in YAML
- Stop signals configurable from YAML
- Port availability checks

### 2. In-Place YAML Updates
The biggest pain point (delete/recreate to change YAML) is being addressed. In 7.23+, you can update YAML of existing custom apps directly — it forces a cleanup but preserves the app entry.

### 3. Docker-in-Container (Portainer/Dockge/Komodo)
MikroTik is adding catalog apps that run Docker inside a container, with web-based management UIs. This signals that they see RouterOS containers as a platform for running more complex stacks, not just simple single-purpose apps.

### 4. IoT and Hardware Integration
OTBR (OpenThread Border Router) and Matter apps show MikroTik positioning routers as smart home hubs — Zigbee/Thread/Matter coordination running natively on the router.

### 5. Better Error Handling
OOM detection, improved YAML error messages, port conflict prevention — the developer experience is maturing.

### What's Still Missing (as of 7.23beta2)
- `c` flag persistence across reboots (our #1 issue)
- Per-container network isolation (all services share one VETH)
- `build:` context (must use pre-built images)
- Service-name DNS resolution (still must use localhost/IPs)
- `/app/remove` for apps without `c` flag

## Known Issues (from our testing on 7.22.1)

These are issues we discovered through practical testing that are NOT documented in the changelog:

1. **`c` (CUSTOM) flag doesn't survive reboot** — all apps lose the flag after restart
2. **Apps without `c` flag can't be `/app/remove`d** — treated as "builtin"
3. **`/app/cleanup` removes data but entry stays** — orphaned disabled entries in the list
4. **Port mapping ignored on bridge1** — `ports: "8090:80"` doesn't mean app is at :8090, it's at :80 on container IP
5. **`www-ssl` and `reverse-proxy` port 443 conflict** — must move WebFig to different port
