# Setup

## Requirements

- Docker
- curl

## Quick Start

```bash
docker run -d --name browser \
  -p 8080:8080 \
  -p 5900:5900 \
  psyb0t/stealthy-auto-browse
```

Port 8080 is the HTTP API. Port 5900 is a noVNC web viewer.

**Verify:** `curl http://localhost:8080/health` returns `ok` when the browser is ready (takes ~10s on first boot).

**Watch the browser:** Open `http://localhost:5900/` in your browser.

## Environment Variables

| Variable | Default | What It Does |
|----------|---------|-------------|
| `XVFB_RESOLUTION` | `1920x1080` | Virtual display resolution. Max 1920x1080 (framebuffer limit). |
| `XVFB_DEPTH` | `24` | Color depth (16/24/32). |
| `TZ` | `UTC` | **Must match IP location** — timezone mismatch is a bot detection signal. |
| `PROXY_URL` | — | HTTP proxy for all browser traffic. Format: `http://user:pass@host:port`. |
| `LOADERS_DIR` | `/loaders` | Directory for page loader YAML files. |
| `USE_VIEWPORT` | `false` | Playwright viewport control. Required for width < ~450px. Reduces stealth. |
| `HTTP_LISTEN_HOST` | `0.0.0.0` | HTTP API bind address. |
| `HTTP_LISTEN_PORT` | `8080` | HTTP API port. |
| `AUTH_TOKEN` | — | If set, all requests (except `/health`) require `Authorization: Bearer <key>` or `?auth_token=<key>` query param. |
| `VNC_LISTEN_HOST` | `0.0.0.0` | VNC bind address. |
| `VNC_LISTEN_PORT` | `5900` | noVNC web viewer port. |

## Common Configurations

```bash
# Match timezone to IP location (important for stealth)
docker run -d -p 8080:8080 -e TZ=Europe/Bucharest psyb0t/stealthy-auto-browse

# Route through proxy
docker run -d -p 8080:8080 -e PROXY_URL=http://user:pass@proxy:8888 psyb0t/stealthy-auto-browse

# Custom resolution
docker run -d -p 8080:8080 -e XVFB_RESOLUTION=1280x720 psyb0t/stealthy-auto-browse

# Persistent profile (cookies, sessions, fingerprint survive restarts)
docker run -d -p 8080:8080 -v ./profile:/userdata psyb0t/stealthy-auto-browse

# Custom listen ports
docker run -d -p 9090:9090 -p 6900:6900 \
  -e HTTP_LISTEN_PORT=9090 -e VNC_LISTEN_PORT=6900 \
  psyb0t/stealthy-auto-browse

# With page loaders
docker run -d -p 8080:8080 -v ./my-loaders:/loaders psyb0t/stealthy-auto-browse
```

## OpenClaw / ClawHub Config

```bash
export STEALTHY_AUTO_BROWSE_URL=http://localhost:8080
```

Or via `~/.openclaw/openclaw.json`:

```json
{
  "skills": {
    "entries": {
      "stealthy-auto-browse": {
        "env": {
          "STEALTHY_AUTO_BROWSE_URL": "http://localhost:8080"
        }
      }
    }
  }
}
```

## Cluster Mode Setup

Run multiple browser instances behind HAProxy with request queuing, sticky sessions, and Redis cookie sync. The number of instances is controlled by `NUM_REPLICAS` (default: 10):

```bash
curl -LO https://raw.githubusercontent.com/psyb0t/docker-stealthy-auto-browse/main/docker-compose.cluster.yml
docker compose -f docker-compose.cluster.yml up -d
```

Entry point is `http://localhost:8080` — same API and MCP endpoint as single-container mode.

Set `STEALTHY_AUTO_BROWSE_URL=http://localhost:8080` as usual.

## Pre-installed Extensions

- **uBlock Origin** — ad/tracker blocking
- **LocalCDN** — serves CDN resources locally
- **ClearURLs** — strips tracking parameters
- **Consent-O-Matic** — auto-handles cookie popups
