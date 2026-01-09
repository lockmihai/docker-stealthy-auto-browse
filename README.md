# docker-stealthy-auto-browse

Stealth browser automation in a container. Camoufox + Xvfb + PyAutoGUI running non-headless with real mouse/keyboard input.

## Why?

Standard browser automation gets detected. Headless browsers leak signals. Chrome DevTools Protocol (CDP) can be detected. Bot detection services fingerprint everything.

This container runs **Camoufox Firefox** with **zero CDP exposure**. Unlike Chromium-based solutions, there's no `Runtime.enable` leak to detect. No fingerprint spoofing = no inconsistencies to detect. Combined with PyAutoGUI for real OS-level input events.

## What's Inside

| Component | Purpose |
|-----------|---------|
| **Camoufox** | Custom Firefox build, no CDP leaks |
| **Xvfb** | Virtual framebuffer - run non-headless without a physical display |
| **noVNC** | Web-based VNC client to watch the browser remotely |
| **PyAutoGUI** | OS-level mouse/keyboard input (not DOM events) |
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
- [Known Limitations](#known-limitations)
- [License](#license)

## HTTP API

The container exposes an HTTP API on port 8080.

### Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | POST | Execute browser commands |
| `/screenshot/browser` | GET | Get browser viewport screenshot as PNG |
| `/screenshot/desktop` | GET | Get full desktop screenshot as PNG |
| `/state` | GET | Get browser state as JSON |
| `/health` | GET | Health check |

### Example Commands

```bash
# Navigate to URL
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "goto", "url": "https://example.com"}'

# Human-like click (real mouse movement + click)
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "human_click", "x": 500, "y": 300}'

# Human-like typing (variable delays between keys)
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "human_type", "text": "hello world"}'

# Send keyboard key (pyautogui)
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "send_key", "key": "enter"}'

# Send key combo
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "send_key", "key": "ctrl+a"}'

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

# Set display resolution
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "set_resolution", "width": 1280, "height": 720}'

# Reset display resolution to original
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "reset_resolution"}'

# Get current resolution info
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "get_resolution"}'

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
| `goto` | `url`, `wait_until` | Navigate to URL |
| `click` | `selector` | Playwright click (DOM event) |
| `mouse_move` | `x`, `y`, `duration` | Human-like mouse movement |
| `mouse_click` | `x`, `y` (optional) | PyAutoGUI click (OS-level) |
| `human_click` | `x`, `y`, `duration` | Human-like move + click |
| `scroll` | `amount`, `x`, `y` | Scroll page (negative = down) |
| `calibrate` | - | Get window offset for coordinate mapping |
| `set_resolution` | `width`, `height` | Change display resolution (width < 450 requires `USE_VIEWPORT=true`) |
| `reset_resolution` | - | Reset display to original resolution |
| `get_resolution` | - | Get current and original display resolution |
| `enter_fullscreen` | - | Enter browser fullscreen mode (hides browser chrome) |
| `exit_fullscreen` | - | Exit browser fullscreen mode |
| `human_type` | `text`, `interval` | Human-like typing with delays |
| `send_key` | `key` | Send keyboard key via pyautogui (e.g., `enter`, `backspace`, `ctrl+a`) |
| `fill` | `selector`, `value` | Fill input field |
| `type` | `selector`, `text`, `delay` | Type into element |
| `eval` | `expression` | Execute JavaScript |
| `get_interactive_elements` | `visible_only` (bool) | Get clickable elements |
| `get_text` | - | Get page text content |
| `get_html` | - | Get page HTML |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `XVFB_RESOLUTION` | `1920x1080` | Virtual display resolution (WxH, max 1920x1080) |
| `XVFB_DEPTH` | `24` | Color depth (16, 24, or 32) |
| `TZ` | `UTC` | Timezone (e.g., `Europe/Bucharest`, `America/New_York`). Set to match your IP location. |
| `LANG` | `en_US.UTF-8` | Locale for browser language |
| `USE_VIEWPORT` | `false` | Enable Playwright viewport control. Required for resolutions < 450px width (mobile). **Warning:** May reduce stealth - only use for targets that don't need maximum stealth. |

**Important:** Set `TZ` to match your IP's geographic location to avoid detection. Example:

```bash
docker run -d -e TZ=Europe/Bucharest -p 8080:8080 -p 5900:5900 psyb0t/stealthy-auto-browse
```

**Mobile viewport example** (for testing mobile layouts on sites that don't need stealth):

```bash
docker run -d \
  -e USE_VIEWPORT=true \
  -e XVFB_RESOLUTION=375x812 \
  -p 8080:8080 -p 5900:5900 \
  psyb0t/stealthy-auto-browse
```

## Persistent Profiles

Mount a directory to `/userdata` to persist cookies, localStorage, extensions, and session data across container restarts.

```bash
docker run -d \
  -p 8080:8080 \
  -p 5900:5900 \
  -v ./my-profile:/userdata \
  psyb0t/stealthy-auto-browse
```

## Browser Extensions

The following extensions are **pre-installed** in the container:

| Extension | Purpose |
|-----------|---------|
| **uBlock Origin** | Blocks ads, trackers, and annoyances |
| **LocalCDN** | Serves common JS libraries locally (prevents CDN tracking) |
| **ClearURLs** | Strips tracking parameters from URLs (utm_*, fbclid, etc.) |
| **Consent-O-Matic** | Auto-handles cookie consent popups |

Additional extensions can be installed via the persistent profile:

1. Mount a profile directory: `-v ./my-profile:/userdata`
2. Open VNC at `http://localhost:5900/`
3. Navigate to `about:addons` and install extensions
4. Extensions persist across restarts

## VNC Access

Watch the browser in real-time via noVNC:

```bash
docker run -d -p 5900:5900 psyb0t/stealthy-auto-browse
```

Open `http://localhost:5900/` (auto-connects).

## Bot Detection Test Results

Tested against major bot detection services (January 2025):

| Site | Result | Notes |
|------|--------|-------|
| [SannySoft](https://bot.sannysoft.com/) | ✅ Pass | All Intoli + fingerprint scanner tests pass |
| [Incolumitas](https://bot.incolumitas.com/) | ✅ Pass | All new detection tests OK |
| [Rebrowser Bot Detector](https://bot-detector.rebrowser.net/) | ✅ Pass | No CDP leaks, no webdriver, viewport OK |
| [CreepJS](https://abrahamjuliot.github.io/creepjs/) | ✅ Pass | 0% stealth detected, chromium: false |
| [BrowserScan](https://www.browserscan.net/bot-detection) | ✅ Pass | WebDriver, CDP, Navigator all "Normal" |
| [Pixelscan](https://pixelscan.net/) | ✅ Pass | Bot check passed (set TZ to match IP for full pass) |
| [BrowserLeaks WebRTC](https://browserleaks.com/webrtc) | ✅ Pass | No WebRTC IP leak |
| [DeviceAndBrowserInfo](https://deviceandbrowserinfo.com/are_you_a_bot) | ✅ Pass | "You are human!" - all 19 checks green |
| [IpHey](https://iphey.com/) | ✅ Pass | "Trustworthy" rating |
| [Fingerprint.com](https://fingerprint.com/demo/) | ✅ Pass | Identified as normal Firefox, no bot flags |

### Why It Works

- **No CDP exposure** - Camoufox is Firefox-based, no Chrome DevTools Protocol to detect
- **No fingerprint spoofing** - Main context matches web workers (no inconsistencies)
- `navigator.webdriver` returns `false`
- Real OS-level input via PyAutoGUI (not DOM events)

### Known Limitations

- **Behavioral analysis** - The `human_click` and `human_type` actions are basic
- **ML-based detection** - Current implementation doesn't have realistic human patterns
- **Timezone** - Set `TZ` env var to match your IP's location to avoid mismatch detection

## License

**WTFPL** - Do What The Fuck You Want To Public License
