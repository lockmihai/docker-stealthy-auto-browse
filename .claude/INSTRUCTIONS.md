# Stealth Browser Instructions

You have access to a stealth browser running in a Docker container. It's Camoufox (Firefox-based, no CDP leaks) with PyAutoGUI for OS-level input. Use it to browse websites without getting detected as a bot.

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

1. **Set TZ to match IP location** - If the timezone doesn't match where the IP says you are, bot detectors may flag it. The user should set `-e TZ=Europe/Bucharest` or whatever matches their IP.

2. **Resize screenshots before viewing** - Use the `whLargest` query param to cap the largest side at 512px (keeps aspect ratio):
   ```bash
   curl -s "http://localhost:8080/screenshot/browser?whLargest=512" -o /tmp/screen.png
   ```
   Other resize options: `?width=800`, `?height=300`, `?width=400&height=400` (exact).

3. **Prefer system input for keyboard** - `system_type` and `send_key` generate real OS-level keystrokes that are undetectable. Playwright's `type` and `fill` work but are detectable if the site looks hard enough.

4. **Build reusable scripts for repeated actions** - If you're doing the same shit over and over (screenshots, clicking, typing), write a helper script in /tmp and source/import it. Don't keep repeating the same curl commands. Example:
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

5. **Mouse input is flexible** - Both Playwright `click` and PyAutoGUI `system_click` do smooth mouse movements. Use whichever fits - Playwright when you have a CSS selector, system_click when you have coordinates.

## How to Interact

**Navigate:**
```bash
curl -s -X POST "http://localhost:8080" -H "Content-Type: application/json" \
  -d '{"action": "goto", "url": "https://example.com"}'
```

**Take screenshot (always resize):**
```bash
curl -s "http://localhost:8080/screenshot/browser?whLargest=512" -o /tmp/screen.png
```

**Find clickable elements:**
```bash
curl -s -X POST "http://localhost:8080" -H "Content-Type: application/json" \
  -d '{"action": "get_interactive_elements"}'
```
Returns elements with `x`, `y` coordinates and `selector` you can use.

**Click by coordinates (PyAutoGUI):**
```bash
curl -s -X POST "http://localhost:8080" -H "Content-Type: application/json" \
  -d '{"action": "system_click", "x": 500, "y": 300}'
```

**Click by selector (Playwright):**
```bash
curl -s -X POST "http://localhost:8080" -H "Content-Type: application/json" \
  -d '{"action": "click", "selector": "button#submit"}'
```

**Type text (undetectable):**
```bash
curl -s -X POST "http://localhost:8080" -H "Content-Type: application/json" \
  -d '{"action": "system_type", "text": "hello world"}'
```

**Send key (undetectable):**
```bash
curl -s -X POST "http://localhost:8080" -H "Content-Type: application/json" \
  -d '{"action": "send_key", "key": "enter"}'
```

**Key combos:**
```bash
curl -s -X POST "http://localhost:8080" -H "Content-Type: application/json" \
  -d '{"action": "send_key", "key": "ctrl+a"}'
```

**Scroll (negative = down):**
```bash
curl -s -X POST "http://localhost:8080" -H "Content-Type: application/json" \
  -d '{"action": "scroll", "amount": -3}'
```

**Fill input by selector (detectable but convenient):**
```bash
curl -s -X POST "http://localhost:8080" -H "Content-Type: application/json" \
  -d '{"action": "fill", "selector": "input[name=email]", "value": "test@example.com"}'
```

**Get page text:**
```bash
curl -s -X POST "http://localhost:8080" -H "Content-Type: application/json" \
  -d '{"action": "get_text"}'
```

**Run JavaScript:**
```bash
curl -s -X POST "http://localhost:8080" -H "Content-Type: application/json" \
  -d '{"action": "eval", "expression": "document.title"}'
```

## Typical Workflow

1. `goto` the URL
2. `get_text` to understand what's on the page - this is usually enough
3. If text isn't clear, `get_html` to see the structure
4. If still confused, take a screenshot to see the visual layout
5. Once you understand the page, `get_interactive_elements` to find what to click and their coordinates
6. `system_click` or `click` to interact
7. `system_type` for text input, `send_key` for Enter/Tab/Escape
8. `get_text` again to verify the result (screenshot only if needed)

## What's Running

- **Camoufox** - Firefox with no CDP exposure (undetectable by CDP checks)
- **Xvfb** - Virtual display at 1920x1080
- **PyAutoGUI** - Real OS-level mouse/keyboard
- **noVNC** - Watch the browser at `http://localhost:5900`

Pre-installed extensions: uBlock Origin, LocalCDN, ClearURLs, Consent-O-Matic (auto-handles cookie popups).
