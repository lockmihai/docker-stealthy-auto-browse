# STEALTHY AUTO-BROWSE

```
    ╦ ╦╔═╗╔═╗╦╔═  ╔╦╗╦ ╦╔═╗  ╔═╗╦  ╔═╗╔╗╔╔═╗╔╦╗
    ╠═╣╠═╣║  ╠╩╗   ║ ╠═╣║╣   ╠═╝║  ╠═╣║║║║╣  ║
    ╩ ╩╩ ╩╚═╝╩ ╩   ╩ ╩ ╩╚═╝  ╩  ╩═╝╩ ╩╝╚╝╚═╝ ╩
```

**THEY DON'T WANT YOU TO SCRAPE. SCRAPE ANYWAY.**

Cloudflare? Datadome? PerimeterX? Akamai? **FUCK 'EM.** This container runs a real browser that looks like a real human because it basically is one. Brave + Patchright + Xvfb + PyAutoGUI = invisible.

`navigator.webdriver` returns `false`. Their JavaScript fingerprinting sees a normal person. Their behavioral analysis sees real mouse movements. You're a ghost in their machine.

---

## THE ARSENAL

| Weapon | Purpose |
|--------|---------|
| **Brave Browser** | Privacy-first, shields up, fingerprint resistance baked in |
| **Patchright** | Playwright but actually stealthy - patches the detection vectors |
| **Xvfb** | Virtual display - run "non-headless" without a monitor |
| **noVNC** | Watch your bot work from any browser. Voyeurism for hackers. |
| **PyAutoGUI + xdotool** | REAL mouse movements. REAL keystrokes. Not that fake DOM event garbage. |
| **HTTP API** | Control everything remotely. Point and shoot. |

---

## QUICK START - GET IN LOSER, WE'RE SCRAPING

```bash
docker run -d --name browser \
  -p 8080:8080 \
  -p 5900:5900 \
  -v ./my-profile:/userdata \
  psyb0t/stealthy-auto-browse
```

**BOOM.** You've got:
- **Port 8080** - HTTP API. Send commands. Get data.
- **Port 5900** - noVNC. Watch the chaos unfold.
- **`/userdata`** - Persistent profile. Cookies, sessions, the works.

Want to hit a URL on startup? Just add it:
```bash
docker run -d psyb0t/stealthy-auto-browse https://their-protected-site.com
```

---

## TABLE OF CONTENTS

- [The API - Your Remote Control](#the-api---your-remote-control)
- [Environment Variables](#environment-variables)
- [Persistent Profiles - Keep Your Sessions](#persistent-profiles)
- [VNC - Watch The Magic](#vnc-access)
- [Known Issues - Nothing's Perfect](#known-issues)

---

## THE API - YOUR REMOTE CONTROL

The container runs `main.py` - an HTTP API that lets you puppet the browser.

### Endpoints

| Endpoint | Method | What It Does |
|----------|--------|--------------|
| `/` | POST | Execute commands. The main event. |
| `/screenshot` | GET | Grab a PNG of what's on screen |
| `/state` | GET | Browser state as JSON |
| `/health` | GET | Is this thing on? |

### Commands - POST /

Send JSON. Get results. It's that simple.

```bash
# GO SOMEWHERE
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "goto", "url": "https://example.com"}'

# TAKE A SCREENSHOT
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "screenshot"}'

# CLICK LIKE A HUMAN - Real mouse movement, real click
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "human_click", "x": 500, "y": 300}'

# TYPE LIKE A HUMAN - Variable delays between keystrokes
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "human_type", "text": "hack the planet"}'

# PLAYWRIGHT CLICK - When you need selector precision
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "click", "selector": "button#submit"}'

# FILL A FORM
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "fill", "selector": "input[name=email]", "value": "crash@override.net"}'

# SCROLL - Negative = down, like a normal person
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "scroll", "amount": -3}'

# FIND CLICKABLE SHIT
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "get_interactive_elements"}'

# GET THE TEXT
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "get_text"}'

# RUN JAVASCRIPT - Execute anything
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "eval", "expression": "document.title"}'

# CALIBRATE - Get window offset for coordinate mapping
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "calibrate"}'

# BURN IT DOWN
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "close"}'
```

### Full Action Reference

| Action | Parameters | What It Does |
|--------|------------|--------------|
| `ping` | - | Health check, returns current URL |
| `close` | - | Kill the browser, shut it down |
| `screenshot` | `full_page` (bool) | Screenshot as base64 |
| `goto` | `url`, `wait_until` | Navigate somewhere |
| `click` | `selector` | Playwright click (DOM events) |
| `mouse_move` | `x`, `y`, `duration` | Move mouse like a human |
| `mouse_click` | `x`, `y` (optional) | PyAutoGUI click (real input) |
| `human_click` | `x`, `y`, `duration` | Move + click, fully human |
| `scroll` | `amount`, `x`, `y` | Scroll the page |
| `calibrate` | - | Get window offset for coords |
| `human_type` | `text`, `interval` | Type with human timing |
| `fill` | `selector`, `value` | Fill input field instantly |
| `type` | `selector`, `text`, `delay` | Type into element |
| `eval` | `expression` | Run JavaScript |
| `get_interactive_elements` | `visible_only` (bool) | Find clickable elements |
| `get_text` | - | Extract page text |
| `get_html` | - | Get raw HTML |

---

## ENVIRONMENT VARIABLES

| Variable | Default | What It Controls |
|----------|---------|------------------|
| `XVFB_RESOLUTION` | `1920x1080x24` | Virtual screen size (WxHxDepth) |

---

## PERSISTENT PROFILES

Mount a directory to `/userdata`. Your cookies, localStorage, extensions, login sessions - all preserved between runs.

```bash
docker run -d \
  -p 8080:8080 \
  -p 5900:5900 \
  -v ./my-profile:/userdata \
  psyb0t/stealthy-auto-browse
```

Log in once. Stay logged in forever. They'll never know you're not human.

---

## VNC ACCESS

Watch your bot in action. Debug visually. Feel like a l33t h4x0r.

```bash
docker run -d -p 5900:5900 psyb0t/stealthy-auto-browse
```

Open `http://localhost:5900/vnc.html` - click Connect - enjoy the show.

---

## KNOWN ISSUES

### Patchright Driver Fuckery

The patchright pip package ships with an unpatched driver. Yeah, really. The whole point of patchright and they forgot to patch it.

**Fix:** Always pass `--disable-blink-features=AutomationControlled` in your args. The included main.py and browser.py already do this for you.

### This Isn't Magic

This beats basic detection - `navigator.webdriver`, JavaScript checks, simple fingerprinting. But if you're up against:

- **Behavioral analysis** - Use `human_click` and `human_type`. Move the mouse like a person. Add random delays. Don't click 100 things per second.
- **Canvas/WebGL fingerprinting** - Brave's shields help but aren't bulletproof
- **Advanced ML detection** - You need to actually act human. Random scroll patterns. Reading delays. The works.

The tools are here. How you use them is on you.

---

## LICENSE

**WTFPL** - Do What The Fuck You Want To Public License

*Mess with the best, die like the rest.*
