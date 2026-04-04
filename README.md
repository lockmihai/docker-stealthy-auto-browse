# docker-stealthy-auto-browse

Stealth browser automation that actually works. A Docker container running Camoufox (custom Firefox) with zero Chrome DevTools Protocol exposure, real OS-level mouse and keyboard input, and a dead-simple HTTP API to control it all.

Passes Cloudflare, CreepJS, BrowserScan, Pixelscan, and every other bot detector we've thrown at it. While Chromium-based tools are getting caught by the first line of defense, this thing walks through the front door unnoticed.

## What's Inside

| Component     | What It Does                                                                                                                                                                                |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Camoufox**  | A custom build of Firefox with zero Chrome DevTools Protocol exposure. Bot detectors look for CDP signals — this browser simply doesn't have any.                                           |
| **Xvfb**      | Virtual framebuffer that lets the browser run with a full graphical display inside a container, no physical monitor needed. This matters because headless mode is another detection signal. |
| **PyAutoGUI** | Generates real OS-level mouse movements and keystrokes. The browser receives these as genuine user input — it has no idea it's being automated.                                             |
| **noVNC**     | Web-based VNC client so you can watch the browser in real time from your own browser. Great for debugging and seeing exactly what's happening.                                              |
| **HTTP API**  | A JSON API on port 8080 that lets you control everything — navigate pages, click elements, type text, take screenshots, manage tabs, handle cookies, and more.                              |
| **MCP Server**| [Model Context Protocol](https://modelcontextprotocol.io/) server at `/mcp` on the same port. AI agents (Claude, etc.) can drive the browser directly over MCP using Streamable HTTP.      |

Pre-installed extensions: **uBlock Origin** (ads/trackers), **LocalCDN** (prevents CDN tracking), **ClearURLs** (strips tracking params), **Consent-O-Matic** (auto-handles cookie popups).

## Quick Start

```bash
docker run -d --name browser \
  -p 8080:8080 \
  -p 5900:5900 \
  psyb0t/stealthy-auto-browse
```

Port **8080** is the HTTP API, port **5900** is the VNC viewer (`http://localhost:5900/`).

**Navigate:**

```bash
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "goto", "url": "https://example.com"}'
```

**Get page text:**

```bash
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "get_text"}'
```

**Click with a real mouse movement (undetectable):**

```bash
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{"action": "system_click", "x": 500, "y": 300}'
```

**Take a screenshot:**

```bash
curl http://localhost:8080/screenshot/browser?whLargest=512 -o screenshot.png
```

See [docs/api.md](docs/api.md) for all actions and the full API reference.

## Table of Contents

- [Two Input Modes](#two-input-modes)
- [MCP Server](#mcp-server)
- [Script Mode](#script-mode)
- [Page Loaders](#page-loaders)
- [Cluster Mode](#cluster-mode)
- [Configuration](#configuration)
- [Bot Detection Results](#bot-detection-results)
- [License](#license)

## MCP Server

AI agents can control the browser over the [Model Context Protocol](https://modelcontextprotocol.io/) via Streamable HTTP at `/mcp` on the same port 8080. All browser actions are exposed as MCP tools — navigation, screenshots, clicking, typing, JavaScript evaluation, cookies, and more.

Connect any MCP-compatible client (Claude Desktop, Claude Code, custom agents) to `http://localhost:8080/mcp/` and start browsing.

Works in both standalone and [cluster mode](#cluster-mode) — HAProxy routes MCP traffic with the same sticky sessions as the HTTP API.

## Two Input Modes

There are two ways to interact with pages. **System input** uses PyAutoGUI to generate real OS-level mouse and keyboard events — the browser cannot tell these apart from a real human. **Playwright input** uses CSS selectors and DOM event injection — easier, but theoretically detectable by behavioral analysis. Use system input on any site with bot protection.

Full breakdown and usage guide: [docs/stealth.md](docs/stealth.md)

## Script Mode

Pipe a YAML script into the container, get JSON results on stdout, container exits. No HTTP server. Good for CI, cron jobs, one-shot scraping.

```bash
cat my-script.yaml | docker run --rm -i \
  -e TARGET_URL=https://example.com \
  psyb0t/stealthy-auto-browse --script > results.json
```

Full docs: [docs/script-mode.md](docs/script-mode.md)

## Page Loaders

Define URL patterns + action sequences in YAML files. Mount them at `/loaders`. Whenever `goto` matches a pattern, the loader runs automatically — removes popups, waits for content, cleans up the page. Greasemonkey for the HTTP API.

Full docs: [docs/page-loaders.md](docs/page-loaders.md)

## Cluster Mode

Run 10 browser instances behind HAProxy with a request queue, sticky sessions, and Redis cookie sync. Download the compose file and HAProxy config, then start:

```bash
curl -LO https://raw.githubusercontent.com/psyb0t/docker-stealthy-auto-browse/main/docker-compose.cluster.yml
curl -LO https://raw.githubusercontent.com/psyb0t/docker-stealthy-auto-browse/main/haproxy.cfg.template
docker compose -f docker-compose.cluster.yml up -d
```

Cookies set on any instance propagate to all others instantly via Redis PubSub. Log in once, the whole fleet is authenticated.

Full docs: [docs/cluster-mode.md](docs/cluster-mode.md)

## Configuration

Full environment variables table, proxy setup, persistent profiles, browser extensions, and VNC access: [docs/configuration.md](docs/configuration.md)

## Bot Detection Results

| Service                                                                | Result   | What They Check                                                         |
| ---------------------------------------------------------------------- | -------- | ----------------------------------------------------------------------- |
| [CreepJS](https://abrahamjuliot.github.io/creepjs/)                    | **Pass** | Canvas/WebGL fingerprint consistency, lies detection, worker comparison |
| [BrowserScan](https://www.browserscan.net/bot-detection)               | **Pass** | WebDriver flag, CDP signals, navigator properties                       |
| [Pixelscan](https://pixelscan.net/)                                    | **Pass** | Fingerprint coherence, timezone/IP match, WebRTC leaks                  |
| [Cloudflare](https://cloudflare.com)                                   | **Pass** | Challenge pages, Turnstile, bot management                              |
| [SannySoft](https://bot.sannysoft.com/)                                | **Pass** | Intoli + fingerprint scanner tests                                      |
| [Incolumitas](https://bot.incolumitas.com/)                            | **Pass** | Modern detection techniques                                             |
| [Rebrowser](https://bot-detector.rebrowser.net/)                       | **Pass** | CDP leak detection, webdriver, viewport analysis                        |
| [BrowserLeaks WebRTC](https://browserleaks.com/webrtc)                 | **Pass** | WebRTC IP leak detection                                                |
| [DeviceAndBrowserInfo](https://deviceandbrowserinfo.com/are_you_a_bot) | **Pass** | 19 checks, all green, "You are human!"                                  |
| [IpHey](https://iphey.com/)                                            | **Pass** | "Trustworthy" rating                                                    |
| [Fingerprint.com](https://fingerprint.com/demo/)                       | **Pass** | Identified as normal Firefox, no bot flags                              |

Why it works: [docs/stealth.md](docs/stealth.md)

## License

**WTFPL** — Do What The Fuck You Want To Public License
