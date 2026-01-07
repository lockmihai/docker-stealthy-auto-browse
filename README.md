# docker-stealthy-auto-browse

Stealth browser automation in a container. Brave + Patchright + Xvfb + PyAutoGUI running non-headless with real mouse/keyboard input.

## Why?

Standard browser automation gets detected. Headless browsers leak signals. Playwright's `navigator.webdriver` returns `true`. Bot detection services fingerprint everything.

This container runs a **real non-headless Brave browser** inside a virtual display with all the stealth patches applied. `navigator.webdriver` returns `false`, fingerprinting sees a normal browser, and PyAutoGUI generates real OS-level input events instead of DOM events.

## What's Inside

| Component | Purpose |
|-----------|---------|
| **Brave Browser** | Privacy-focused browser with built-in fingerprint resistance |
| **Patchright** | Playwright fork with anti-detection patches applied |
| **Xvfb** | Virtual framebuffer - run non-headless without a physical display |
| **noVNC** | Web-based VNC client to watch the browser remotely |
| **PyAutoGUI + xdotool** | OS-level mouse/keyboard input (not DOM events) |
| **HTTP API** | JSON API to control the browser remotely |

## Quick Start

```bash
docker run -d --name browser \
  -p 8080:8080 \
  -p 5900:5900 \
  -v ./my-profile:/userdata \
  psyb0t/stealthy-auto-browse
```

- **Port 8080** - HTTP API for browser control
- **Port 5900** - noVNC web interface
- **`/userdata`** - Persistent browser profile (cookies, sessions, etc.)

Open a URL on startup:
```bash
docker run -d psyb0t/stealthy-auto-browse https://example.com
```

## Table of Contents

- [HTTP API](#http-api)
- [Actions Reference](#actions-reference)
- [Environment Variables](#environment-variables)
- [Persistent Profiles](#persistent-profiles)
- [VNC Access](#vnc-access)
- [Known Issues](#known-issues)
- [License](#license)

## HTTP API

The container exposes an HTTP API on port 8080.

### Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | POST | Execute browser commands |
| `/screenshot` | GET | Get current screenshot as PNG |
| `/state` | GET | Get browser state as JSON |
| `/health` | GET | Health check |

### Example Commands

```bash
# Navigate to URL
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "goto", "url": "https://example.com"}'

# Take screenshot (returns base64)
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "screenshot"}'

# Human-like click (real mouse movement + click)
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "human_click", "x": 500, "y": 300}'

# Human-like typing (variable delays between keys)
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "human_type", "text": "hello world"}'

# Playwright click (CSS selector)
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "click", "selector": "button#submit"}'

# Fill form field
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "fill", "selector": "input[name=email]", "value": "test@example.com"}'

# Scroll page
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "scroll", "amount": -3}'

# Get interactive elements
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "get_interactive_elements"}'

# Get page text
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "get_text"}'

# Execute JavaScript
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "eval", "expression": "document.title"}'

# Calibrate coordinate offset
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "calibrate"}'

# Close browser
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "close"}'
```

## Actions Reference

| Action | Parameters | Description |
|--------|------------|-------------|
| `ping` | - | Health check, returns current URL |
| `close` | - | Close browser and shutdown |
| `screenshot` | `full_page` (bool) | Screenshot as base64 |
| `goto` | `url`, `wait_until` | Navigate to URL |
| `click` | `selector` | Playwright click (DOM event) |
| `mouse_move` | `x`, `y`, `duration` | Human-like mouse movement |
| `mouse_click` | `x`, `y` (optional) | PyAutoGUI click (OS-level) |
| `human_click` | `x`, `y`, `duration` | Human-like move + click |
| `scroll` | `amount`, `x`, `y` | Scroll page (negative = down) |
| `calibrate` | - | Get window offset for coordinate mapping |
| `human_type` | `text`, `interval` | Human-like typing with delays |
| `fill` | `selector`, `value` | Fill input field |
| `type` | `selector`, `text`, `delay` | Type into element |
| `eval` | `expression` | Execute JavaScript |
| `get_interactive_elements` | `visible_only` (bool) | Get clickable elements |
| `get_text` | - | Get page text content |
| `get_html` | - | Get page HTML |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `XVFB_RESOLUTION` | `1920x1080x24` | Virtual display resolution (WxHxDepth) |

## Persistent Profiles

Mount a directory to `/userdata` to persist cookies, localStorage, extensions, and session data across container restarts.

```bash
docker run -d \
  -p 8080:8080 \
  -p 5900:5900 \
  -v ./my-profile:/userdata \
  psyb0t/stealthy-auto-browse
```

## VNC Access

Watch the browser in real-time via noVNC:

```bash
docker run -d -p 5900:5900 psyb0t/stealthy-auto-browse
```

Open `http://localhost:5900/vnc.html` and click Connect.

## Known Issues

### Detection Limitations

This handles basic detection vectors:
- `navigator.webdriver` returns `false`
- JavaScript fingerprint checks pass
- Basic bot detection is bypassed

What this does NOT handle well (yet):
- **Behavioral analysis** - The `human_click` and `human_type` actions are basic and will get flagged by serious behavioral analysis
- **Canvas/WebGL fingerprinting** - Brave's shields help but aren't perfect
- **ML-based detection** - Current implementation doesn't have realistic human patterns

## License

**WTFPL** - Do What The Fuck You Want To Public License
