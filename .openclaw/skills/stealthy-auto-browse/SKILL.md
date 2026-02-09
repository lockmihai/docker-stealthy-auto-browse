---
name: stealthy-auto-browse
description: Browser automation that passes CreepJS, BrowserScan, Pixelscan, and Cloudflare — zero CDP exposure, OS-level input, persistent fingerprints. Use when standard browser skills get 403s or CAPTCHAs.
homepage: https://github.com/psyb0t/docker-stealthy-auto-browse
user-invocable: true
metadata:
  { "openclaw": { "emoji": "🕵️", "primaryEnv": "STEALTHY_AUTO_BROWSE_URL", "requires": { "bins": ["docker", "curl"] } } }
---

# stealthy-auto-browse

## Why Not Just Use agent-browser?

Standard browser skills (agent-browser, etc.) use Playwright + Chromium which exposes Chrome DevTools Protocol signals. Bot detection services like Cloudflare, DataDome, PerimeterX, and Akamai detect these instantly. This skill uses Camoufox (custom Firefox) with zero CDP exposure and real OS-level mouse/keyboard input — completely invisible to behavioral analysis.

## When To Use This Skill

- Target site has bot detection (Cloudflare, DataDome, PerimeterX, Akamai)
- Target site blocks headless browsers or returns CAPTCHAs
- You need to maintain a logged-in session without getting banned
- Standard browser skill is getting 403s or blocked responses
- You need to scrape data from sites with anti-bot protection

## When NOT To Use This Skill

- Simple page fetches with no bot protection (use curl/WebFetch instead)
- Sites that don't care about automation (use agent-browser, it's faster)
- You only need to read static HTML (use curl)

## Setup

**1. Run the container:**

```bash
docker run -d -p 8080:8080 -p 5900:5900 psyb0t/stealthy-auto-browse
```

**2. Configure environment:**

```bash
export STEALTHY_AUTO_BROWSE_URL=http://localhost:8080
```

Or via OpenClaw config (`~/.openclaw/openclaw.json`):

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

**3. Verify:** `curl $STEALTHY_AUTO_BROWSE_URL/health` should return `ok`. VNC viewer at http://localhost:5900.

## Key Concepts

**Two input modes:**

1. **System methods** (`system_click`, `system_type`, `mouse_move`, `send_key`) — OS-level input via PyAutoGUI, completely undetectable. Use these for stealth.
2. **Playwright methods** (`click`, `fill`, `type`) — CSS/XPath selector-based, faster but detectable by behavioral analysis.

**Workflow for undetectable browsing:**

1. `goto` — navigate to page
2. `get_interactive_elements` — find all clickable elements with x,y coordinates
3. `system_click` — click at coordinates (real mouse movement)
4. `system_type` — type text (real keystrokes)
5. Take screenshot to verify — `GET /screenshot/browser?whLargest=512`

## API Reference

All commands: POST `$STEALTHY_AUTO_BROWSE_URL/` with JSON `{"action": "<name>", ...params}`.

### Navigation

**goto** — Navigate to URL

```json
{"action": "goto", "url": "https://example.com", "wait_until": "domcontentloaded"}
```

`wait_until`: `domcontentloaded` (default), `load`, `networkidle`

### Undetectable Input (Prefer These)

**system_click** — Move mouse + click at coordinates

```json
{"action": "system_click", "x": 500, "y": 300, "duration": 0.3}
```

**mouse_move** — Move mouse without clicking

```json
{"action": "mouse_move", "x": 500, "y": 300, "duration": 0.5}
```

**mouse_click** — Click at position (current or specified)

```json
{"action": "mouse_click", "x": 500, "y": 300}
```

**system_type** — Type text via OS keyboard

```json
{"action": "system_type", "text": "hello world", "interval": 0.08}
```

**send_key** — Send keyboard key or combo

```json
{"action": "send_key", "key": "enter"}
{"action": "send_key", "key": "ctrl+a"}
```

**scroll** — Scroll page (negative = down)

```json
{"action": "scroll", "amount": -3}
{"action": "scroll", "amount": 5, "x": 500, "y": 300}
```

### Playwright Input (Detectable)

**click** — Click by CSS selector or XPath

```json
{"action": "click", "selector": "#submit-btn"}
{"action": "click", "selector": "xpath=//button[@id='submit-btn']"}
```

**fill** — Fill input field (clears first)

```json
{"action": "fill", "selector": "input[name='email']", "value": "user@example.com"}
```

**type** — Type into element with delay

```json
{"action": "type", "selector": "#search", "text": "query", "delay": 0.05}
```

### Tab Management

**list_tabs** — Get all open tabs

```json
{"action": "list_tabs"}
```

**new_tab** — Open new tab (optionally navigate)

```json
{"action": "new_tab", "url": "https://example.com"}
```

**switch_tab** — Switch to tab by index

```json
{"action": "switch_tab", "index": 0}
```

**close_tab** — Close current tab

```json
{"action": "close_tab"}
```

### Dialog Handling

**handle_dialog** — Pre-configure next dialog response (must call BEFORE triggering the dialog)

```json
{"action": "handle_dialog", "accept": true}
{"action": "handle_dialog", "accept": true, "text": "prompt response"}
{"action": "handle_dialog", "accept": false}
```

**get_last_dialog** — Get info about the last dialog

```json
{"action": "get_last_dialog"}
```

Returns `type` (alert/confirm/prompt), `message`, `default_value`, `buttons`.

### Cookie & Storage Management

**get_cookies** — Get all cookies

```json
{"action": "get_cookies"}
```

**set_cookie** — Set a cookie

```json
{"action": "set_cookie", "name": "key", "value": "val", "url": "https://example.com"}
```

**delete_cookies** — Clear all cookies

```json
{"action": "delete_cookies"}
```

**get_storage** / **set_storage** / **clear_storage** — localStorage/sessionStorage

```json
{"action": "get_storage", "type": "local"}
{"action": "set_storage", "type": "local", "key": "k", "value": "v"}
{"action": "clear_storage", "type": "session"}
```

### Downloads & Uploads

**get_last_download** — Get info about last downloaded file

```json
{"action": "get_last_download"}
```

**upload_file** — Set file on a file input element

```json
{"action": "upload_file", "selector": "#file-input", "file_path": "/tmp/file.txt"}
```

### Network Logging

**enable_network_log** / **disable_network_log** — Toggle request/response logging

```json
{"action": "enable_network_log"}
{"action": "disable_network_log"}
```

**get_network_log** — Get captured requests/responses

```json
{"action": "get_network_log"}
```

**clear_network_log** — Clear the log

```json
{"action": "clear_network_log"}
```

### Wait Conditions

**wait_for_element** — Wait for element to appear (CSS or XPath)

```json
{"action": "wait_for_element", "selector": "#loaded", "timeout": 10}
{"action": "wait_for_element", "selector": "xpath=//div[@class='done']", "timeout": 10}
```

**wait_for_text** — Wait for text to appear on page

```json
{"action": "wait_for_text", "text": "Success", "timeout": 10}
```

**wait_for_url** — Wait for URL to match pattern

```json
{"action": "wait_for_url", "url": "**/dashboard", "timeout": 10}
```

**wait_for_network_idle** — Wait for no network activity

```json
{"action": "wait_for_network_idle", "timeout": 30}
```

### Page Inspection

**get_interactive_elements** — Get all clickable elements with coordinates

```json
{"action": "get_interactive_elements", "visible_only": true}
```

Returns elements with `tag`, `text`, `selector`, `x`, `y`, `w`, `h`, `visible`. Use `x` and `y` with `system_click` for undetectable clicks.

**get_text** — Get visible text content

```json
{"action": "get_text"}
```

**get_html** — Get full page HTML

```json
{"action": "get_html"}
```

**eval** — Execute JavaScript

```json
{"action": "eval", "expression": "document.title"}
```

### Screenshots

**GET /screenshot/browser** — Browser viewport PNG
**GET /screenshot/desktop** — Full desktop PNG

Resize query parameters (all optional):

| Parameter | Effect |
|-----------|--------|
| `whLargest=512` | Set largest side to 512px, keep aspect ratio |
| `width=800` | Resize to 800px wide, keep aspect ratio |
| `height=300` | Resize to 300px tall, keep aspect ratio |
| `width=400&height=400` | Exact dimensions |

```bash
curl $STEALTHY_AUTO_BROWSE_URL/screenshot/browser?whLargest=512 -o screenshot.png
```

### State & Utility

**GET /state** — Current URL, title, window offset
**GET /health** — Returns "ok"

**ping** — Check connection

```json
{"action": "ping"}
```

**calibrate** — Recalculate window offset for coordinate mapping

```json
{"action": "calibrate"}
```

**get_resolution** — Get display resolution

```json
{"action": "get_resolution"}
```

**enter_fullscreen** / **exit_fullscreen** — Toggle browser fullscreen

```json
{"action": "enter_fullscreen"}
{"action": "exit_fullscreen"}
```

**close** — Shut down browser

```json
{"action": "close"}
```

## Container Options

```bash
# Custom resolution
docker run -d -p 8080:8080 -e XVFB_RESOLUTION=1280x720 psyb0t/stealthy-auto-browse

# Match timezone to IP location (important for stealth)
docker run -d -p 8080:8080 -e TZ=Europe/Bucharest psyb0t/stealthy-auto-browse

# HTTP proxy
docker run -d -p 8080:8080 -e PROXY_URL=http://user:pass@proxy:8888 psyb0t/stealthy-auto-browse

# Persistent browser profile (cookies, sessions, fingerprint)
docker run -d -p 8080:8080 -v ./profile:/userdata psyb0t/stealthy-auto-browse

# Open URL on startup
docker run -d -p 8080:8080 psyb0t/stealthy-auto-browse https://example.com
```

## Example: Undetectable Login

```bash
API=$STEALTHY_AUTO_BROWSE_URL

# Navigate
curl -X POST $API -H "Content-Type: application/json" \
  -d '{"action": "goto", "url": "https://example.com/login"}'

# Find elements
curl -X POST $API -H "Content-Type: application/json" \
  -d '{"action": "get_interactive_elements"}'

# Click email field and type (undetectable)
curl -X POST $API -H "Content-Type: application/json" \
  -d '{"action": "system_click", "x": 400, "y": 200}'
curl -X POST $API -H "Content-Type: application/json" \
  -d '{"action": "system_type", "text": "user@example.com"}'

# Click password field and type
curl -X POST $API -H "Content-Type: application/json" \
  -d '{"action": "system_click", "x": 400, "y": 260}'
curl -X POST $API -H "Content-Type: application/json" \
  -d '{"action": "system_type", "text": "password123"}'

# Submit
curl -X POST $API -H "Content-Type: application/json" \
  -d '{"action": "system_click", "x": 400, "y": 320}'

# Verify with screenshot
curl "$API/screenshot/browser?whLargest=512" -o result.png
```

## Response Format

```json
{
  "success": true,
  "timestamp": 1234567890.123,
  "data": { ... },
  "error": "message if failed"
}
```

## Tips

1. **Use `get_interactive_elements`** to find coordinates before clicking
2. **Prefer system methods** (`system_click`, `system_type`) for stealth
3. **Add delays** between actions to appear human
4. **Use `calibrate`** if coordinate clicks seem offset
5. **Match `TZ`** to your IP's geographic location
6. **Use `whLargest=512`** on screenshots to keep them manageable
7. **Mount `/userdata`** for persistent cookies, sessions, and fingerprint across restarts
8. **Use `wait_for_element`** instead of `sleep` when waiting for page content
9. **Use `handle_dialog`** before triggering alerts/confirms/prompts
