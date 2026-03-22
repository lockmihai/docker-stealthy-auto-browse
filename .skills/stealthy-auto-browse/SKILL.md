---
name: stealthy-auto-browse
description: Browser automation that passes CreepJS, BrowserScan, Pixelscan, and Cloudflare — zero CDP exposure, OS-level input, persistent fingerprints. Use when standard browser skills get 403s or CAPTCHAs.
homepage: https://github.com/psyb0t/docker-stealthy-auto-browse
user-invocable: true
metadata:
  { "openclaw": { "emoji": "🕵️", "primaryEnv": "STEALTHY_AUTO_BROWSE_URL", "requires": { "bins": ["docker", "curl"] } } }
---

# stealthy-auto-browse

Stealth browser in Docker. Camoufox (custom Firefox) — zero CDP signals. OS-level mouse/keyboard via PyAutoGUI — undetectable. Passes Cloudflare, DataDome, PerimeterX, Akamai.

For installation, configuration, and container setup, see [references/setup.md](references/setup.md).

## When To Use

- Site has bot detection (Cloudflare, CAPTCHAs, DataDome)
- Another browser skill is getting 403s or blocked responses
- You need a logged-in session that won't get banned

## When NOT To Use

- No bot protection — use `curl` or `WebFetch`
- Only need static HTML — use `curl`

## Setup

The API should already be running. Set the base URL:

```bash
export STEALTHY_AUTO_BROWSE_URL=http://localhost:8080
```

**Verify:** `curl $STEALTHY_AUTO_BROWSE_URL/health` returns `ok`.

## HTTP API

All commands: `POST $STEALTHY_AUTO_BROWSE_URL/` with JSON body `{"action": "name", ...params}`.

Every response:

```json
{
  "success": true,
  "timestamp": 1234567890.123,
  "data": { ... },
  "error": "only when success is false"
}
```

## Two Input Modes

### System Input — Undetectable

Uses PyAutoGUI for real OS-level events. The browser has no idea it's automated.

- `system_click` — move mouse with human-like curve, then click (viewport x,y coords)
- `mouse_move` — move mouse without clicking (hover menus, tooltips)
- `mouse_click` — click at position or current location (no smooth movement)
- `system_type` — type text character-by-character with randomized delays
- `send_key` — press a key or combo (`enter`, `tab`, `ctrl+a`)
- `scroll` — mouse wheel scroll (negative = down)

Get viewport coordinates from `get_interactive_elements`.

### Playwright Input — Detectable But Convenient

Uses Playwright's DOM events. Faster, uses CSS selectors/XPath, but detectable.

- `click` — click by selector
- `fill` — set input value instantly
- `type` — type into element character-by-character

### Which To Use

- **Bot detection?** System input. Always.
- **No detection?** Playwright input is fine.
- **Fill forms stealthily?** `system_click` to focus, then `system_type`.

## Typical Workflow

1. `goto` → load the page
2. `get_text` → read what's on the page
3. `get_interactive_elements` → find buttons/inputs with x,y coordinates
4. `system_click` / `system_type` / `send_key` → interact
5. `wait_for_element` / `wait_for_text` → wait for results
6. `get_text` → verify

## Actions Reference

### Navigation

```json
{"action": "goto", "url": "https://example.com"}
{"action": "goto", "url": "https://example.com", "wait_until": "networkidle"}
{"action": "goto", "url": "https://example.com", "referer": "https://google.com/search?q=stuff"}
{"action": "refresh"}
{"action": "refresh", "wait_until": "networkidle"}
```

`wait_until`: `"domcontentloaded"` (default), `"load"`, `"networkidle"`.
`referer`: set HTTP Referer header (for sites that check referrer).

Response: `{"url": "...", "title": "..."}`

### System Input (Undetectable)

```json
{"action": "system_click", "x": 500, "y": 300}
{"action": "system_click", "x": 500, "y": 300, "duration": 0.5}
{"action": "mouse_move", "x": 500, "y": 300}
{"action": "mouse_click", "x": 500, "y": 300}
{"action": "mouse_click"}
{"action": "system_type", "text": "hello world", "interval": 0.08}
{"action": "send_key", "key": "enter"}
{"action": "send_key", "key": "ctrl+a"}
{"action": "scroll", "amount": -3}
{"action": "scroll", "amount": -3, "x": 500, "y": 300}
```

### Playwright Input (Detectable)

```json
{"action": "click", "selector": "#submit-btn"}
{"action": "click", "selector": "xpath=//button[@id='submit']"}
{"action": "fill", "selector": "input[name='email']", "value": "user@example.com"}
{"action": "type", "selector": "#search", "text": "query", "delay": 0.05}
```

### Page Inspection

```json
{"action": "get_interactive_elements"}
{"action": "get_interactive_elements", "visible_only": true}
{"action": "get_text"}
{"action": "get_html"}
{"action": "eval", "expression": "document.title"}
{"action": "eval", "expression": "document.querySelectorAll('a').length"}
```

`get_interactive_elements` returns all buttons, links, inputs with `x`, `y`, `w`, `h`, `text`, `selector`, `visible`. Pass `x`, `y` directly to `system_click`.

`get_text` returns visible page text (truncated to 10,000 chars). Call this first after navigating.

### Screenshots

```bash
# Browser viewport
curl -s "$STEALTHY_AUTO_BROWSE_URL/screenshot/browser?whLargest=512" -o screenshot.png

# Full desktop
curl -s "$STEALTHY_AUTO_BROWSE_URL/screenshot/desktop?whLargest=512" -o desktop.png
```

Resize params: `whLargest=512` (recommended), `width=800`, `height=300`, `width=400&height=400`.

Via action (for script mode — returns base64 with `output_id`):

```json
{"action": "save_screenshot"}
{"action": "save_screenshot", "type": "desktop"}
{"action": "save_screenshot", "output_id": "my_screenshot", "whLargest": 512}
{"action": "save_screenshot", "path": "/output/page.png"}
```

### Wait Conditions

Use these instead of `sleep`.

```json
{"action": "wait_for_element", "selector": "#results", "state": "visible", "timeout": 10}
{"action": "wait_for_text", "text": "Search results", "timeout": 10}
{"action": "wait_for_url", "url": "**/dashboard", "timeout": 10}
{"action": "wait_for_network_idle", "timeout": 30}
```

`state`: `"visible"` (default), `"hidden"`, `"attached"`, `"detached"`.

### Tabs

```json
{"action": "list_tabs"}
{"action": "new_tab", "url": "https://example.com"}
{"action": "switch_tab", "index": 0}
{"action": "close_tab", "index": 1}
```

### Dialogs

Call `handle_dialog` BEFORE the action that triggers the dialog. Dialogs are auto-accepted by default.

```json
{"action": "handle_dialog", "accept": true}
{"action": "handle_dialog", "accept": false}
{"action": "handle_dialog", "accept": true, "text": "prompt response"}
{"action": "get_last_dialog"}
```

### Cookies

```json
{"action": "get_cookies"}
{"action": "get_cookies", "urls": ["https://example.com"]}
{"action": "set_cookie", "name": "session", "value": "abc", "url": "https://example.com"}
{"action": "delete_cookies"}
```

### Storage

```json
{"action": "get_storage", "type": "local"}
{"action": "set_storage", "type": "local", "key": "theme", "value": "dark"}
{"action": "clear_storage", "type": "local"}
```

`type`: `"local"` (default) or `"session"`.

### Downloads & Uploads

```json
{"action": "get_last_download"}
{"action": "upload_file", "selector": "#file-input", "file_path": "/tmp/doc.pdf"}
```

### Network Logging

```json
{"action": "enable_network_log"}
{"action": "get_network_log"}
{"action": "clear_network_log"}
{"action": "getclear_network_log"}
{"action": "disable_network_log"}
```

### Console Logging

Capture `console.log`, `console.error`, `console.warn`, etc. Each entry has `type`, `text`, `location`, `timestamp`.

```json
{"action": "enable_console_log"}
{"action": "get_console_log"}
{"action": "clear_console_log"}
{"action": "getclear_console_log"}
{"action": "disable_console_log"}
```

### Scrolling

```json
{"action": "scroll_to_bottom", "delay": 0.4}
{"action": "scroll_to_bottom_humanized", "min_clicks": 2, "max_clicks": 6, "delay": 0.5}
```

`scroll_to_bottom` uses JS (fast). `scroll_to_bottom_humanized` uses OS-level mouse wheel (undetectable).

### Display

```json
{"action": "calibrate"}
{"action": "get_resolution"}
{"action": "enter_fullscreen"}
{"action": "exit_fullscreen"}
```

Call `calibrate` after fullscreen changes.

### Utility

```json
{"action": "ping"}
{"action": "sleep", "duration": 2}
{"action": "close"}
```

### State Endpoints (GET)

```bash
curl $STEALTHY_AUTO_BROWSE_URL/health     # "ok" when ready
curl $STEALTHY_AUTO_BROWSE_URL/state      # {"status", "url", "title", "window_offset"}
```

## Script Mode

Pipe a YAML script via stdin, get JSON results on stdout, container exits. No HTTP server.

```bash
cat my-script.yaml | docker run --rm -i \
  -e TARGET_URL=https://example.com \
  psyb0t/stealthy-auto-browse --script > results.json
```

### Script Format

```yaml
name: Scrape Example
on_error: stop    # "stop" (default) or "continue"
steps:
  - action: goto
    url: ${env.TARGET_URL}
    wait_until: networkidle
  - action: sleep
    duration: 2
  - action: save_screenshot
    output_id: screenshot
  - action: get_text
    output_id: page_text
  - action: eval
    expression: "document.title"
    output_id: title
```

### Output

```json
{
  "name": "Scrape Example",
  "success": true,
  "steps_executed": 5,
  "steps_total": 5,
  "duration": 3.42,
  "step_results": [ ... ],
  "outputs": {
    "screenshot": "data:image/png;base64,iVBOR...",
    "page_text": { "text": "...", "length": 1234 },
    "title": { "result": "Example Domain" }
  }
}
```

- **`output_id`** on any step collects its result into `outputs`. Screenshots become base64 data URIs.
- **`${env.VAR_NAME}`** substitutes environment variables.
- **`on_error: continue`** keeps going past failures. `stop` (default) halts.
- **All HTTP API actions** work as script steps.
- **Logs go to stderr**, stdout is clean JSON.
- **Exit code** 0 on success, 1 on failure.

### Example: Screenshot + Extract

```bash
cat <<'EOF' | docker run --rm -i -e URL=https://example.com \
  psyb0t/stealthy-auto-browse --script > results.json
name: Quick Scrape
steps:
  - action: goto
    url: ${env.URL}
    wait_until: networkidle
  - action: save_screenshot
    output_id: screenshot
    whLargest: 1024
  - action: get_text
    output_id: text
  - action: eval
    expression: "document.title"
    output_id: title
EOF
```

## Page Loaders (URL-Triggered Automation)

Mount YAML files to `/loaders`. When `goto` hits a matching URL, the loader's steps execute instead of normal navigation. Works in both API and script mode.

```bash
docker run -d -p 8080:8080 -v ./my-loaders:/loaders psyb0t/stealthy-auto-browse
```

In script mode:

```bash
cat script.yaml | docker run --rm -i \
  -v ./my-loaders:/loaders \
  psyb0t/stealthy-auto-browse --script
```

### Loader Format

```yaml
name: News Site Cleanup
match:
  domain: news-site.com       # exact hostname (www. stripped)
  path_prefix: /articles      # path starts with
  regex: "article/\\d+"       # full URL regex
steps:
  - action: goto
    url: "${url}"              # ${url} = original URL
    wait_until: networkidle
  - action: eval
    expression: "document.querySelector('.cookie-banner')?.remove()"
  - action: wait_for_element
    selector: "article"
    timeout: 10
```

Match fields are optional but at least one is required. All specified fields must match.

## Tips

1. **Always `get_interactive_elements` before clicking** — don't guess coordinates
2. **System input for stealth** — `system_click`, `system_type`, `send_key`
3. **`get_text` first, screenshots second** — text is faster and smaller
4. **Match TZ to IP location** — timezone mismatch is a detection signal
5. **Resize screenshots with `?whLargest=512`** — full resolution is huge
6. **Wait conditions over sleep** — `wait_for_element`, `wait_for_text`, `wait_for_url`
7. **`handle_dialog` BEFORE the trigger** — dialogs are auto-accepted otherwise
8. **`calibrate` after fullscreen** — coordinate mapping shifts
