# docker-stealthy-auto-browse

Stealth browser automation in a container. Camoufox + Xvfb + PyAutoGUI running non-headless with real mouse/keyboard input.

## Table of Contents

- [Why?](#why)
- [What's Inside](#whats-inside)
- [Quick Start](#quick-start)
- [OpenClaw / ClawHub Skill](#openclaw--clawhub-skill)
- [Claude Code Integration](#claude-code-integration)
- [HTTP API](#http-api)
- [Actions Reference](#actions-reference)
- [Environment Variables](#environment-variables)
- [Testing](#testing)
- [Page Loaders](#page-loaders)
- [Persistent Profiles](#persistent-profiles)
- [Browser Extensions](#browser-extensions)
- [VNC Access](#vnc-access)
- [Bot Detection Test Results](#bot-detection-test-results)
- [License](#license)

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

## OpenClaw / ClawHub Skill

This project is available as an [OpenClaw](https://docs.openclaw.ai/) skill on [ClawHub](https://clawhub.ai/psyb0t/stealthy-auto-browse). Install it and any OpenClaw-compatible agent can use the browser on demand.

**Install:**

```bash
clawhub install psyb0t/stealthy-auto-browse
```

**Configure** (`~/.openclaw/openclaw.json`):

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

The skill loads on demand when browser automation is needed — it won't consume tokens until the agent actually needs to browse. Start the container with `docker run -d -p 8080:8080 -p 5900:5900 psyb0t/stealthy-auto-browse` and the agent handles the rest.

## Claude Code Integration

This container works great with [Claude Code](https://claude.ai/code). Claude can launch the browser, navigate pages, read content, click elements, and fill forms - all through the HTTP API.

For a ready-to-use Claude Code setup, check out [docker-claude-code](https://github.com/psyb0t/docker-claude-code).

See [`.claude/INSTRUCTIONS.md`](.claude/INSTRUCTIONS.md) for the full guide Claude uses to control the browser.

## HTTP API

The container exposes an HTTP API on port 8080.

### Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | POST | Execute browser commands |
| `/screenshot/browser` | GET | Get browser viewport screenshot as PNG (supports resize query params) |
| `/screenshot/desktop` | GET | Get full desktop screenshot as PNG (supports resize query params) |
| `/state` | GET | Get browser state as JSON |
| `/health` | GET | Health check |

### Example Commands

```bash
# Navigate to URL
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "goto", "url": "https://example.com"}'

# System-level click (PyAutoGUI mouse movement + click)
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "system_click", "x": 500, "y": 300}'

# System-level typing (PyAutoGUI with variable delays)
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "system_type", "text": "hello world"}'

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

# Get current resolution info
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "get_resolution"}'

# Open a new tab
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "new_tab", "url": "https://example.com"}'

# List all open tabs
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "list_tabs"}'

# Switch to tab by index
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "switch_tab", "index": 0}'

# Close a tab by index
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "close_tab", "index": 1}'

# Get all cookies
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "get_cookies"}'

# Set a cookie
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "set_cookie", "name": "session", "value": "abc123", "url": "https://example.com"}'

# Delete all cookies
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "delete_cookies"}'

# Pre-configure dialog handling (accept/dismiss next dialog)
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "handle_dialog", "accept": true, "text": "my prompt response"}'

# Get info about the last dialog
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "get_last_dialog"}'

# Upload a file to a file input
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "upload_file", "selector": "input[type=file]", "file_path": "/tmp/document.pdf"}'

# Wait for an element to appear
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "wait_for_element", "selector": "#results", "state": "visible", "timeout": 10}'

# Wait for specific text to appear on page
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "wait_for_text", "text": "Success", "timeout": 15}'

# Wait for URL to match a pattern
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "wait_for_url", "url": "**/dashboard", "timeout": 10}'

# Enable network request/response logging
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "enable_network_log"}'

# Get captured network log
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "get_network_log"}'

# Close browser
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "close"}'
```

## Actions Reference

### Navigation

| Action | Parameters | Description |
|--------|------------|-------------|
| `goto` | `url`, `wait_until` | Navigate to URL |
| `back` | - | Go back in browser history |
| `forward` | - | Go forward in browser history |
| `refresh` | - | Reload current page |

### Playwright Input (DOM Events)

| Action | Parameters | Description |
|--------|------------|-------------|
| `click` | `selector` | Playwright click on a CSS selector (DOM event) |
| `fill` | `selector`, `value` | Fill input field (clears existing value first) |
| `type` | `selector`, `text`, `delay` | Type into element character by character |

### System Input (OS-Level via PyAutoGUI)

| Action | Parameters | Description |
|--------|------------|-------------|
| `mouse_move` | `x`, `y`, `duration` | Human-like mouse movement to coordinates |
| `mouse_click` | `x`, `y` (optional) | PyAutoGUI click at position or current location |
| `system_click` | `x`, `y`, `duration` | PyAutoGUI move + click (combined) |
| `scroll` | `amount`, `x`, `y` | Scroll page (negative = down) |
| `scroll_to_bottom` | `delay` | Fast JS scroll to bottom, triggers lazy loading |
| `scroll_to_bottom_humanized` | `min_clicks`, `max_clicks`, `delay` | OS-level humanized scroll to bottom |
| `system_type` | `text`, `interval` | PyAutoGUI typing with variable delays |
| `send_key` | `key` | Send keyboard key via PyAutoGUI (e.g., `enter`, `backspace`, `ctrl+a`) |

### Tab Management

| Action | Parameters | Description |
|--------|------------|-------------|
| `list_tabs` | - | List all open tabs with URLs and active status |
| `new_tab` | `url`, `wait_until` | Open a new tab, optionally navigate to URL |
| `switch_tab` | `index` | Switch to tab by index |
| `close_tab` | `index` (optional) | Close tab by index, or close active tab |

### Dialog Handling

| Action | Parameters | Description |
|--------|------------|-------------|
| `handle_dialog` | `accept` (bool), `text` | Pre-configure how to handle the next browser dialog (alert/confirm/prompt) |
| `get_last_dialog` | - | Get info about the last dialog that appeared (type, message, buttons) |

### Cookie Management

| Action | Parameters | Description |
|--------|------------|-------------|
| `get_cookies` | `urls` (optional list) | Get all cookies, optionally filtered by URLs |
| `set_cookie` | `name`, `value`, `url`, ... | Set a cookie (accepts all Playwright cookie fields) |
| `delete_cookies` | - | Delete all cookies |

### Storage

| Action | Parameters | Description |
|--------|------------|-------------|
| `get_storage` | `type` (`local`/`session`) | Get all localStorage or sessionStorage items |
| `set_storage` | `type`, `key`, `value` | Set a storage item |
| `clear_storage` | `type` (`local`/`session`) | Clear localStorage or sessionStorage |

### Downloads

| Action | Parameters | Description |
|--------|------------|-------------|
| `get_last_download` | - | Get info about the last downloaded file (url, filename, path) |

### Network Logging

| Action | Parameters | Description |
|--------|------------|-------------|
| `enable_network_log` | - | Start capturing network requests and responses |
| `disable_network_log` | - | Stop capturing network traffic |
| `get_network_log` | - | Get captured network log entries |
| `clear_network_log` | - | Clear all captured network log entries |

### Wait Conditions

| Action | Parameters | Description |
|--------|------------|-------------|
| `wait_for_element` | `selector`, `state`, `timeout` | Wait for element to reach state (`visible`, `hidden`, `attached`, `detached`) |
| `wait_for_text` | `text`, `timeout` | Wait for text to appear on the page |
| `wait_for_url` | `url`, `timeout` | Wait for URL to match a pattern (supports globs like `**/dashboard`) |
| `wait_for_network_idle` | `timeout` | Wait for network activity to settle |

### File Upload

| Action | Parameters | Description |
|--------|------------|-------------|
| `upload_file` | `selector`, `file_path` | Upload a file to a file input element |

### Page Inspection

| Action | Parameters | Description |
|--------|------------|-------------|
| `get_interactive_elements` | `visible_only` (bool) | Get clickable/interactive elements on the page |
| `get_text` | - | Get page text content (up to 10,000 chars) |
| `get_html` | - | Get full page HTML |
| `eval` | `expression` | Execute JavaScript and return the result |

### Display & Calibration

| Action | Parameters | Description |
|--------|------------|-------------|
| `calibrate` | - | Get window offset for coordinate mapping |
| `get_resolution` | - | Get current display resolution |
| `enter_fullscreen` | - | Enter browser fullscreen mode (hides browser chrome) |
| `exit_fullscreen` | - | Exit browser fullscreen mode |

### Utility

| Action | Parameters | Description |
|--------|------------|-------------|
| `ping` | - | Health check, returns current URL |
| `close` | - | Close browser and shutdown |
| `sleep` | `duration` | Wait for N seconds |

### Screenshot Resize

Both screenshot endpoints accept optional query parameters for resizing:

| Parameter | Description |
|-----------|-------------|
| `width` | Resize to this width, keep aspect ratio |
| `height` | Resize to this height, keep aspect ratio |
| `width` + `height` | Resize to exact dimensions (ignores aspect ratio) |
| `whLargest` | Set the largest side (width or height) to this value, keep aspect ratio |

```bash
# Resize to 512px on longest side (aspect ratio preserved)
curl http://localhost:8080/screenshot/browser?whLargest=512 -o screenshot.png

# Resize to 800px wide (aspect ratio preserved)
curl http://localhost:8080/screenshot/browser?width=800 -o screenshot.png

# Resize to exact 400x400 (stretches)
curl http://localhost:8080/screenshot/browser?width=400&height=400 -o screenshot.png

# Desktop screenshot resized to 300px tall
curl http://localhost:8080/screenshot/desktop?height=300 -o screenshot.png
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `XVFB_RESOLUTION` | `1920x1080` | Virtual display resolution (WxH) |
| `XVFB_DEPTH` | `24` | Color depth (16, 24, or 32) |
| `TZ` | `UTC` | Timezone (e.g., `Europe/Bucharest`, `America/New_York`). Set to match your IP location. |
| `LANG` | `en_US.UTF-8` | Locale for browser language |
| `USE_VIEWPORT` | `false` | Enable Playwright viewport control. Required for narrow widths (Firefox has a ~450px minimum without it). **Warning:** May reduce stealth. |
| `LOADERS_DIR` | `/loaders` | Directory containing YAML page loaders |
| `PROXY_URL` | - | HTTP proxy URL for all browser traffic (e.g., `http://user:pass@host:port`) |

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

## Testing

Tests are located in the `tests/` directory. Run the full test suite with:

```bash
./test.sh
```

Run specific tests by passing their names as arguments:

```bash
./test.sh test_proxy test_upload_file
```

## Page Loaders

Mount a directory of YAML files to `/loaders` to define URL-triggered automation. When `goto` matches a loader, the loader's steps run instead of the default navigation. Each step is an API action — same format as POST body.

```bash
docker run -d -p 8080:8080 -p 5900:5900 \
  -v ./loaders:/loaders \
  psyb0t/stealthy-auto-browse
```

Example loader (`loaders/my_loader.yaml`):
```yaml
name: Clean Up Example.com
match:
  domain: example.com       # exact hostname (strips www.)
  path_prefix: /page        # URL path starts with
  # regex: "example\\.com/page/\\d+"  # or use regex
steps:
  - action: goto
    url: "${url}"            # ${url} = the original URL
    wait_until: networkidle
  - action: sleep
    duration: 1
  - action: eval
    expression: "document.querySelector('.popup')?.remove()"
  - action: scroll_to_bottom
    delay: 0.4
```

All match fields are optional (at least one required). All must match for the loader to trigger. See `loaders/` directory for real examples.

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
| [SannySoft](https://bot.sannysoft.com/) | Pass | All Intoli + fingerprint scanner tests pass |
| [Incolumitas](https://bot.incolumitas.com/) | Pass | All new detection tests OK |
| [Rebrowser Bot Detector](https://bot-detector.rebrowser.net/) | Pass | No CDP leaks, no webdriver, viewport OK |
| [CreepJS](https://abrahamjuliot.github.io/creepjs/) | Pass | 0% stealth detected, chromium: false |
| [BrowserScan](https://www.browserscan.net/bot-detection) | Pass | WebDriver, CDP, Navigator all "Normal" |
| [Pixelscan](https://pixelscan.net/) | Pass | Bot check passed (set TZ to match IP for full pass) |
| [BrowserLeaks WebRTC](https://browserleaks.com/webrtc) | Pass | No WebRTC IP leak |
| [DeviceAndBrowserInfo](https://deviceandbrowserinfo.com/are_you_a_bot) | Pass | "You are human!" - all 19 checks green |
| [IpHey](https://iphey.com/) | Pass | "Trustworthy" rating |
| [Fingerprint.com](https://fingerprint.com/demo/) | Pass | Identified as normal Firefox, no bot flags |

### Why It Works

- **No CDP exposure** - Camoufox is Firefox-based, no Chrome DevTools Protocol to detect
- **No fingerprint spoofing** - Main context matches web workers (no inconsistencies)
- `navigator.webdriver` returns `false`
- Real OS-level input via PyAutoGUI (not DOM events)

## License

**WTFPL** - Do What The Fuck You Want To Public License
