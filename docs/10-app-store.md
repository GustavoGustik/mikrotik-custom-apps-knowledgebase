# Custom App Stores

RouterOS 7.22+ supports custom app stores — HTTP-served YAML arrays of app definitions that appear in the WinBox/WebFig app catalog.

## How App Stores Work

1. You create a YAML file containing an array of app definitions
2. Host it on any HTTP/HTTPS server
3. Configure the URL in RouterOS
4. Apps appear in the catalog alongside built-in ones

## Creating an App Store

### YAML Format

An app store file is a YAML **array** of app definitions (same schema as individual apps, but in a list):

```yaml
- name: bind9
  descr: BIND 9 DNS Server
  page: https://www.isc.org/bind/
  category: networking
  services:
    bind9:
      image: docker.io/internetsystemsconsortium/bind9:9.18
      ports:
        - 53:53/udp:dns
        - 53:53/tcp:dns
      volumes:
        - config:/etc/bind
        - cache:/var/cache/bind
      restart: unless-stopped

- name: my-web-app
  descr: My custom web application
  page: https://example.com
  category: productivity
  default-credentials: admin:admin
  services:
    app:
      image: ghcr.io/myorg/myapp:latest
      ports:
        - 8080:80:web
      environment:
        APP_URL: "[accessProto]://[accessIP]:[accessPort]"
      restart: unless-stopped
```

**Important formatting rules**:
- Use YAML array syntax with `-` prefix
- 2-space indentation
- No `---` separators between entries
- Each entry is a complete app definition

### YAML Validation

Use the app store schema for validation:

```yaml
# yaml-language-server: $schema=https://tikoci.github.io/restraml/routeros-app-yaml-store-schema.latest.json
- name: myapp
  descr: My app
  services:
    # ...
```

VS Code settings:
```json
{
  "yaml.schemas": {
    "https://tikoci.github.io/restraml/routeros-app-yaml-store-schema.latest.json": [
      "*.tikappstore.yaml",
      "*-appstore.yaml"
    ]
  }
}
```

## Hosting Options

### Option 1: Static File Server

```bash
# Simple local server for testing
npx serve .

# Or Python
python3 -m http.server 8000
```

Configure on router:
```
/app/settings set app-store-urls=http://10.0.1.10:8000/myapps.yaml
```

### Option 2: GitHub Pages / Cloudflare Pages

1. Create a GitHub repo with your YAML file
2. Enable GitHub Pages (Settings → Pages → Deploy from branch)
3. Your URL: `https://yourusername.github.io/repo/apps.yaml`

```
/app/settings set app-store-urls=https://yourusername.github.io/repo/apps.yaml
```

### Option 3: Nginx / Caddy

Serve with correct Content-Type:

```nginx
# nginx.conf
location /apps.yaml {
    default_type text/yaml;
    root /var/www/html;
}
```

### MIME Type Requirement

The server MUST return `Content-Type: text/yaml` or `text/yaml; charset=utf-8`.

**Known issues**:
- GitLab Pages may add extra charset parameters that cause parsing failures
- GitHub Pages and Cloudflare Pages work reliably
- Plain nginx/Caddy servers work with correct config

## Configuring on RouterOS

### Add App Store URL

```
/app/settings set app-store-urls=https://example.com/myapps.yaml
```

### Multiple App Stores

```
/app/settings set app-store-urls=https://store1.example.com/apps.yaml,https://store2.example.com/apps.yaml
```

### Verify

After adding the URL:
1. Open WinBox → Apps
2. Your apps should appear in the catalog
3. They can be installed like built-in apps

## Example: Company App Store

```yaml
# company-apps.yaml
- name: internal-dashboard
  descr: Company internal monitoring dashboard
  page: https://git.company.com/dashboard
  category: monitoring
  icon: https://company.com/logo.png
  default-credentials: admin:CompanyPass123
  services:
    dashboard:
      image: ghcr.io/company/dashboard:latest
      ports:
        - 3000:3000:web
      environment:
        API_URL: http://api.company.internal
        TZ: Europe/Prague
      volumes:
        - data:/app/data
      restart: unless-stopped

- name: company-vpn-monitor
  descr: VPN tunnel monitoring with alerts
  page: https://git.company.com/vpn-monitor
  category: networking
  services:
    monitor:
      image: ghcr.io/company/vpn-monitor:latest
      environment:
        ROUTER_API: http://[routerIP]/rest
        ALERT_WEBHOOK: https://hooks.slack.com/xxx
      restart: unless-stopped
```

## Rapid Development Workflow

For testing custom apps during development:

1. **Local HTTP server**:
   ```bash
   cd my-app-store/
   npx serve . -p 8000
   ```

2. **Configure router**:
   ```
   /app/settings set app-store-urls=http://10.0.1.10:8000/apps.yaml
   ```

3. **Edit → Refresh cycle**:
   - Edit YAML locally
   - Disable/remove app on router
   - Re-add from catalog (it fetches fresh YAML)

4. **For inline YAML testing** (no server needed):
   ```
   /app add disabled=no yaml="<paste-yaml-here>"
   ```
