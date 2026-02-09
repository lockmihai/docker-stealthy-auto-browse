# Stealth Browser Instructions

You have access to a stealth browser running in a Docker container. It uses Camoufox (a Firefox fork with zero Chrome DevTools Protocol exposure) and PyAutoGUI for OS-level mouse/keyboard input. Bot detection services like Cloudflare, DataDome, PerimeterX, and Akamai cannot detect it because there are no CDP signals and all input happens at the operating system level.

## Connecting to the Browser

If the user gives you a specific API URL, use that. Otherwise try `http://localhost:8080`.

If the API isn't responding and you need to browse something, launch it yourself:
```bash
docker run -d --rm --name stealthy-browser -p 8080:8080 -p 5900:5900 psyb0t/stealthy-auto-browse
```

Wait a few seconds for it to start, then use `http://localhost:8080`.

When you're done and you launched it yourself, clean up:
```bash
docker stop stealthy-browser
```

## Critical Rules

1. **Set TZ to match IP location** — If the timezone doesn't match where the IP says you are, bot detectors may flag it. The user should set `-e TZ=Europe/Bucharest` or whatever matches their IP.

2. **Resize screenshots before viewing** — Use the `whLargest` query param to cap the largest side at 512px (keeps aspect ratio):
   ```bash
   curl -s "http://localhost:8080/screenshot/browser?whLargest=512" -o /tmp/screen.png
   ```
   Other resize options: `?width=800`, `?height=300`, `?width=400&height=400` (exact).

3. **Prefer system input** — `system_click`, `system_type`, and `send_key` generate real OS-level events that are undetectable. Playwright's `click`, `type`, and `fill` work but are detectable by behavioral analysis. Use system input when stealth matters.

4. **Build reusable scripts for repeated actions** — If you're doing the same shit over and over (screenshots, clicking, typing), write a helper script in /tmp and source/import it. Don't keep repeating the same curl commands. Example:
   ```bash
   # /tmp/browser.sh
   API="${BROWSER_API:-http://localhost:8080}"
   browser_screenshot() { curl -s "$API/screenshot/browser?whLargest=512" -o "${1:-/tmp/screen.png}"; }
   browser_goto() { curl -s -X POST "$API" -H "Content-Type: application/json" -d "{\"action\":\"goto\",\"url\":\"$1\"}"; }
   browser_click() { curl -s -X POST "$API" -H "Content-Type: application/json" -d "{\"action\":\"system_click\",\"x\":$1,\"y\":$2}"; }
   browser_type() { curl -s -X POST "$API" -H "Content-Type: application/json" -d "{\"action\":\"system_type\",\"text\":\"$1\"}"; }
   browser_key() { curl -s -X POST "$API" -H "Content-Type: application/json" -d "{\"action\":\"send_key\",\"key\":\"$1\"}"; }
   ```
   Then `source /tmp/browser.sh` and use `browser_goto "https://example.com"`, `browser_click 500 300`, etc.

5. **Use wait conditions instead of sleep** — `wait_for_element`, `wait_for_text`, `wait_for_url` wait for actual page state, not arbitrary time. Much more reliable.

6. **Handle dialogs proactively** — Call `handle_dialog` BEFORE triggering any action that opens an alert/confirm/prompt, or the page will hang forever waiting for the dialog to be dismissed.

7. **Call `calibrate` after fullscreen changes** — Entering/exiting fullscreen shifts the coordinate mapping between viewport and screen. Recalibrate so `system_click` hits the right spot.

## Understanding the Two Input Modes

### System Input (Undetectable)
Actions: `system_click`, `mouse_move`, `mouse_click`, `system_type`, `send_key`, `scroll`

These generate real OS-level events via PyAutoGUI. The browser receives genuine mouse/keyboard input — no JavaScript or automation API is involved. Websites cannot distinguish these from a real human.

System input works with **viewport coordinates** (x, y pixel positions within the page content area). Get these from `get_interactive_elements`.

### Playwright Input (Detectable)
Actions: `click`, `fill`, `type`

These use Playwright's DOM automation — faster and easier (you use CSS selectors instead of coordinates) but the event injection patterns are theoretically detectable by sophisticated behavioral analysis.

### When to Use Which
- **Stealth-critical** (login forms, Cloudflare-protected pages): Always system input
- **Convenience** (quick scraping, no bot detection): Playwright input is fine
- **system_click vs click**: `system_click` needs x,y coordinates (from `get_interactive_elements`), `click` needs a CSS selector or XPath. Choose based on what you have.
- **system_type vs fill**: `system_type` types character-by-character with randomized delays (human-like). `fill` instantly sets the value (faster but detectable).

## Typical Workflow

1. `goto` the URL
2. `get_text` to understand what's on the page — this is usually enough
3. If text isn't clear enough, `get_html` to see the DOM structure
4. If still confused, take a screenshot to see the visual layout
5. `get_interactive_elements` to find what to click and their coordinates
6. `system_click` or `click` to interact
7. `system_type` for text input, `send_key` for Enter/Tab/Escape
8. `wait_for_element` or `wait_for_text` to wait for results
9. `get_text` again to verify the result

## Actions Reference

All commands: `POST http://localhost:8080/` with JSON body `{"action": "<name>", ...params}`.

Every response has this shape:
```json
{"success": true, "timestamp": 1234567890.123, "data": {...}, "error": "only when success is false"}
```

---

### Navigation

**goto** — Navigate to a URL. The main way to load pages.

```json
{"action": "goto", "url": "https://example.com"}
{"action": "goto", "url": "https://example.com", "wait_until": "networkidle"}
```
- `wait_until`: `"domcontentloaded"` (default, fast), `"load"` (all resources), `"networkidle"` (no network for 500ms, slowest but most complete)
- Returns: `{"url": "...", "title": "..."}`
- If a page loader matches the URL, the loader runs instead and the response includes `"loader": "name"`.

**back / forward / refresh** — Standard browser navigation. No parameters.

---

### System Input (Undetectable)

**system_click** — Moves the mouse to coordinates with a human-like curved path (random jitter, eased acceleration), then clicks. This is the primary way to click things when stealth matters.

```json
{"action": "system_click", "x": 500, "y": 300}
{"action": "system_click", "x": 500, "y": 300, "duration": 0.5}
```
- `x`, `y` (required): Viewport coordinates from `get_interactive_elements`
- `duration` (optional): Mouse movement time in seconds. If omitted, random 0.2-0.6s.
- Returns: `{"system_clicked": {"x": 500, "y": 300}}`

**mouse_move** — Moves the mouse with human-like movement but does NOT click. Use to hover over elements (trigger hover menus/tooltips) or simulate natural mouse behavior.

```json
{"action": "mouse_move", "x": 500, "y": 300}
```
- Returns: `{"moved_to": {"x": 500, "y": 300}}`

**mouse_click** — Clicks at a position or at the current mouse location. Unlike `system_click`, this does NOT do the smooth mouse movement first — it's a direct click.

```json
{"action": "mouse_click"}
{"action": "mouse_click", "x": 500, "y": 300}
```
- `x`, `y` (optional): If omitted, clicks wherever the mouse currently is.
- Returns: `{"clicked_at": {"x": 500, "y": 300}}` or `{"clicked_at": "current"}`
- Use after `mouse_move` when you want to separate movement and click into two steps.

**system_type** — Types text character-by-character via real OS keystrokes. Each key has a randomized delay for realism. You must focus an input first (via `system_click`).

```json
{"action": "system_type", "text": "hello world"}
{"action": "system_type", "text": "hello world", "interval": 0.12}
```
- `text` (required): What to type
- `interval` (optional, default 0.08): Base delay between keys in seconds, jittered +-30ms
- Returns: `{"typed_len": 11}`

**send_key** — Sends a keyboard key or combo via OS input. For Enter, Tab, Escape, arrow keys, Ctrl+A, etc.

```json
{"action": "send_key", "key": "enter"}
{"action": "send_key", "key": "ctrl+a"}
{"action": "send_key", "key": "ctrl+shift+t"}
```
- `key` (required): Key name or combo with `+`. Names: `enter`, `tab`, `escape`, `backspace`, `delete`, `up`, `down`, `left`, `right`, `home`, `end`, `pageup`, `pagedown`, `f1`-`f12`, `ctrl`, `alt`, `shift`, `space`, etc.
- Returns: `{"send_key": "enter"}`

**scroll** — Scrolls using the mouse wheel. Real OS-level scroll events.

```json
{"action": "scroll", "amount": -3}
{"action": "scroll", "amount": 5, "x": 500, "y": 300}
```
- `amount` (default -3): **Negative = scroll down**, positive = scroll up. Each unit is one mouse wheel "click".
- `x`, `y` (optional): Move mouse here first, then scroll. Useful for scrolling inside a specific scrollable element.
- Returns: `{"scrolled": -3}`

---

### Playwright Input (Detectable)

**click** — Clicks an element by CSS selector or XPath. Faster than system_click but detectable.

```json
{"action": "click", "selector": "#submit-btn"}
{"action": "click", "selector": "xpath=//button[@id='submit-btn']"}
```
- Returns: `{"clicked": "#submit-btn"}`

**fill** — Sets an input field's value by selector. Clears existing content first. Instant but detectable (no keystroke events).

```json
{"action": "fill", "selector": "input[name='email']", "value": "user@example.com"}
```
- Returns: `{"filled": "input[name='email']"}`

**type** — Types into an element character-by-character via Playwright. Middle ground between fill (instant) and system_type (OS-level). Generates keystroke events but through Playwright's automation layer.

```json
{"action": "type", "selector": "#search", "text": "query", "delay": 0.05}
```
- Returns: `{"typed": "#search"}`

---

### Screenshots

GET requests, not POST actions.

**GET /screenshot/browser** — Browser viewport as PNG. Always resize to avoid huge images:
```bash
curl -s "http://localhost:8080/screenshot/browser?whLargest=512" -o /tmp/screen.png
```

**GET /screenshot/desktop** — Full virtual desktop including window chrome. Same resize params.

Resize parameters (all optional):
| Parameter | Effect |
|-----------|--------|
| `whLargest=512` | Largest side = 512px, keep aspect ratio. **Use this by default.** |
| `width=800` | 800px wide, keep aspect ratio |
| `height=300` | 300px tall, keep aspect ratio |
| `width=400&height=400` | Exact dimensions |

---

### Page Inspection

**get_interactive_elements** — Returns every interactive element (buttons, links, inputs, etc.) with their viewport coordinates. **Call this before clicking anything** — it tells you what you can interact with and where it is.

```json
{"action": "get_interactive_elements"}
```
- Returns:
```json
{
  "count": 3,
  "elements": [
    {"tag": "button", "text": "Submit", "selector": "#submit", "x": 400, "y": 250, "w": 120, "h": 40, "visible": true},
    {"tag": "input", "text": "", "selector": "input[name='email']", "x": 300, "y": 180, "w": 250, "h": 35, "visible": true}
  ]
}
```
- `x`, `y` = element center — pass directly to `system_click`
- `selector` = CSS selector — use with `click` or `fill`
- `w`, `h` = element dimensions

**get_text** — All visible text from the page body. Truncated to 10,000 chars.

```json
{"action": "get_text"}
```
- Returns: `{"text": "Page heading\nSome content...", "length": 1234}`

**get_html** — Full HTML source of the page.

```json
{"action": "get_html"}
```
- Returns: `{"html": "<!DOCTYPE html>...", "length": 45678}`

**eval** — Execute JavaScript in the page and return the result.

```json
{"action": "eval", "expression": "document.title"}
{"action": "eval", "expression": "document.querySelectorAll('a').length"}
```
- Returns: `{"result": "Example Domain"}`

---

### Wait Conditions

Use these instead of `sleep` — they wait for actual page state, not arbitrary time.

**wait_for_element** — Waits for an element to be visible (or hidden/attached/detached).

```json
{"action": "wait_for_element", "selector": "#results", "timeout": 10}
{"action": "wait_for_element", "selector": ".spinner", "state": "hidden", "timeout": 10}
```
- `state`: `"visible"` (default), `"hidden"`, `"attached"`, `"detached"`
- `timeout` (default 30): Max seconds. Errors if exceeded.

**wait_for_text** — Waits for text to appear anywhere in the page body (substring match).

```json
{"action": "wait_for_text", "text": "Search results", "timeout": 10}
```

**wait_for_url** — Waits for the URL to match a glob pattern. Useful after form submissions/redirects.

```json
{"action": "wait_for_url", "url": "**/dashboard", "timeout": 10}
```
- Supports `*` (any chars except `/`) and `**` (any chars including `/`).

**wait_for_network_idle** — Waits until no network requests for 500ms.

```json
{"action": "wait_for_network_idle", "timeout": 30}
```

---

### Tab Management

The browser supports multiple tabs. One is "active" — all actions operate on it.

**list_tabs** — Returns all tabs with URLs and which is active.
```json
{"action": "list_tabs"}
```
- Returns: `{"count": 2, "tabs": [{"index": 0, "url": "...", "active": false}, {"index": 1, "url": "...", "active": true}]}`

**new_tab** — Opens a new tab (becomes active). Optionally navigates to a URL.
```json
{"action": "new_tab", "url": "https://example.com"}
```
- Returns: `{"index": 1, "url": "..."}`

**switch_tab** — Switches active tab by index.
```json
{"action": "switch_tab", "index": 0}
```

**close_tab** — Closes a tab (current if no index given). Last tab becomes active.
```json
{"action": "close_tab"}
{"action": "close_tab", "index": 1}
```
- Returns: `{"closed": true, "remaining": 1}`

---

### Dialog Handling

**handle_dialog** — **Must call BEFORE the action that triggers the dialog.** Pre-configures how the next alert/confirm/prompt will be handled. If you don't set this up before a dialog appears, the page hangs.

```json
{"action": "handle_dialog", "accept": true}
{"action": "handle_dialog", "accept": false}
{"action": "handle_dialog", "accept": true, "text": "my response"}
```
- `accept`: true = OK, false = Cancel
- `text`: Response for prompt dialogs

**get_last_dialog** — Info about the last dialog that appeared.
```json
{"action": "get_last_dialog"}
```
- Returns: `{"dialog": {"type": "confirm", "message": "Are you sure?", "default_value": "", "buttons": ["ok", "cancel"]}}` or `{"dialog": null}`

---

### Cookies

**get_cookies** — All cookies, or filtered by URL.
```json
{"action": "get_cookies"}
{"action": "get_cookies", "urls": ["https://example.com"]}
```
- Returns: `{"count": 3, "cookies": [{"name": "session", "value": "abc", "domain": ".example.com", ...}]}`

**set_cookie** — Sets a cookie. Needs `name`, `value`, and either `url` or `domain`.
```json
{"action": "set_cookie", "name": "session", "value": "abc123", "url": "https://example.com"}
```

**delete_cookies** — Clears all cookies.
```json
{"action": "delete_cookies"}
```

---

### Storage

Access localStorage/sessionStorage. Must be on the right page (storage is per-origin).

**get_storage** — Returns all items as key-value pairs.
```json
{"action": "get_storage", "type": "local"}
```
- Returns: `{"items": {"theme": "dark", "lang": "en"}, "type": "local"}`

**set_storage** — Sets a single key-value pair.
```json
{"action": "set_storage", "type": "local", "key": "theme", "value": "dark"}
```

**clear_storage** — Clears all items.
```json
{"action": "clear_storage", "type": "session"}
```

---

### Downloads

The browser tracks file downloads automatically.

**get_last_download** — Info about the most recent download.
```json
{"action": "get_last_download"}
```
- Returns: `{"download": {"url": "...", "filename": "file.pdf", "path": "/tmp/.../file.pdf"}}` or `{"download": null}`

---

### Uploads

**upload_file** — Sets a file on an `<input type="file">` without opening the OS file picker. The file must exist inside the container (use `docker cp` to copy files in). You still need to submit the form after this.

```json
{"action": "upload_file", "selector": "#file-input", "file_path": "/tmp/document.pdf"}
```
- Returns: `{"selector": "#file-input", "file": "document.pdf", "size": 12345}`

---

### Network Logging

Record HTTP requests/responses the page makes. Useful for finding API endpoints or debugging.

**enable_network_log** / **disable_network_log** — Toggle recording.
```json
{"action": "enable_network_log"}
{"action": "disable_network_log"}
```

**get_network_log** — Returns captured entries.
```json
{"action": "get_network_log"}
```
- Returns:
```json
{
  "count": 2,
  "log": [
    {"type": "request", "url": "...", "method": "GET", "resource_type": "fetch", "timestamp": 123.456},
    {"type": "response", "url": "...", "status": 200, "timestamp": 123.789}
  ]
}
```
- `resource_type`: fetch, document, stylesheet, script, image, font, etc.

**clear_network_log** — Clears entries but keeps logging on if it was on.

---

### Scrolling

**scroll_to_bottom** — Scrolls the entire page top-to-bottom using JavaScript, then back to top. Triggers lazy-loaded content.
```json
{"action": "scroll_to_bottom", "delay": 0.5}
```

**scroll_to_bottom_humanized** — Same but uses real mouse wheel scrolling with randomized amounts and jittered delays. Undetectable.
```json
{"action": "scroll_to_bottom_humanized", "min_clicks": 2, "max_clicks": 6, "delay": 0.5}
```

---

### Display

**calibrate** — Recalculates the viewport-to-screen coordinate mapping. Call after fullscreen changes or if system_click seems off.
```json
{"action": "calibrate"}
```
- Returns: `{"window_offset": {"x": 0, "y": 74}}`

**get_resolution** — Virtual display resolution.
```json
{"action": "get_resolution"}
```
- Returns: `{"width": 1920, "height": 1080}`

**enter_fullscreen / exit_fullscreen** — Toggle browser fullscreen. Call `calibrate` after.
```json
{"action": "enter_fullscreen"}
{"action": "exit_fullscreen"}
```
- Returns: `{"fullscreen": true, "changed": true}`

---

### Utility

**ping** — Health check, returns current URL.
```json
{"action": "ping"}
```
- Returns: `{"message": "pong", "url": "..."}`

**sleep** — Pause execution. Prefer wait conditions over this.
```json
{"action": "sleep", "duration": 2}
```

**close** — Shuts down the browser and container.
```json
{"action": "close"}
```

**GET /state** — Current browser state (URL, title, window offset).
**GET /health** — Returns `ok` when ready.

---

## Page Loaders

YAML files mounted to `/loaders` that define automated sequences triggered by URL patterns. When `goto` navigates to a matching URL, the loader's steps run instead of default navigation.

```yaml
name: Clean Up Example.com
match:
  domain: example.com       # Exact hostname (www. stripped automatically)
  path_prefix: /articles    # URL path starts with this
  regex: "article/\\d+"     # Full URL matches this regex
steps:
  - action: goto
    url: "${url}"            # ${url} = the original URL
    wait_until: networkidle
  - action: eval
    expression: "document.querySelector('.popup')?.remove()"
```

Match fields are all optional (at least one required). All specified fields must match. The `${url}` placeholder in any string value is replaced with the original URL. Responses include `"loader": "name"` when triggered.

## What's Running

- **Camoufox** — Firefox fork with zero CDP exposure
- **Xvfb** — Virtual display at 1920x1080
- **PyAutoGUI** — Real OS-level mouse/keyboard
- **noVNC** — Watch the browser live at `http://localhost:5900`

Pre-installed extensions: uBlock Origin, LocalCDN, ClearURLs, Consent-O-Matic (auto-handles cookie popups).
