#!/usr/bin/env python3
"""
Interactive browser session with HTTP command interface.

Supports both Playwright (JS) clicks and PyAutoGUI (OS-level) clicks.
PyAutoGUI clicks are undetectable by behavioral analysis.

Endpoints:
    POST /           - Execute command, returns JSON result
    GET /screenshot  - Get current screenshot as PNG
    GET /state       - Get browser state as JSON
    GET /health      - Health check
"""

from __future__ import annotations

import asyncio
import base64
import os
import random
import sys
import time
from datetime import datetime

from aiohttp import web

from browser import Browser, BrowserConfig


# =============================================================================
# LOGGING
# =============================================================================


def _ts() -> str:
    return datetime.now().strftime("%H:%M:%S")


def log(msg: str) -> None:
    print(f"[{_ts()}] {msg}", flush=True)


def log_request(action: str, params: dict | None = None) -> None:
    if params:
        log(f">> {action} {params}")
    else:
        log(f">> {action}")


def log_response(success: bool, msg: str = "") -> None:
    if success:
        log(f"<< OK {msg}" if msg else "<< OK")
    else:
        log(f"<< FAIL {msg}" if msg else "<< FAIL")


# =============================================================================
# GLOBALS
# =============================================================================

# PyAutoGUI imported lazily after display is ready
pyautogui = None

# Global browser instance
browser: Browser | None = None

# Window offset for coordinate translation
WINDOW_OFFSET = {"x": 0, "y": 0}

PORT = 8080
URL = sys.argv[1] if len(sys.argv) > 1 else None


def init_pyautogui():
    """Initialize pyautogui after X display is available."""
    global pyautogui
    if pyautogui is not None:
        return

    xauth_path = os.path.expanduser("~/.Xauthority")
    if not os.path.exists(xauth_path):
        open(xauth_path, "a").close()
    os.environ.setdefault("XAUTHORITY", xauth_path)

    import pyautogui as pag

    pag.FAILSAFE = False
    pag.PAUSE = 0
    pyautogui = pag


def screen_coords(x: int, y: int) -> tuple[int, int]:
    """Convert viewport coords to screen coords."""
    return (x + WINDOW_OFFSET["x"], y + WINDOW_OFFSET["y"])


def get_active_page():
    """Get the currently active page."""
    if not browser or not browser._context:
        return None
    pages = browser._context.pages
    if not pages:
        return None
    return pages[-1]


async def get_window_offset_js(page) -> dict:
    """Get browser window position using JavaScript."""
    try:
        return await page.evaluate(
            """() => ({
                x: window.screenX + window.outerWidth - window.innerWidth,
                y: window.screenY + window.outerHeight - window.innerHeight
            })"""
        )
    except Exception:
        return {"x": 0, "y": 0}


def human_move_mouse(x: int, y: int, duration: float | None = None) -> None:
    """Move mouse with human-like behavior."""
    assert pyautogui is not None
    if duration is None:
        duration = random.uniform(0.2, 0.6)

    screen_x, screen_y = screen_coords(x, y)
    jitter = random.randint(-3, 3)
    target_x, target_y = screen_x + jitter, screen_y + jitter
    current_x, current_y = pyautogui.position()

    distance = ((target_x - current_x) ** 2 + (target_y - current_y) ** 2) ** 0.5
    steps = max(int(distance / 50), 10)

    for i in range(steps + 1):
        t = 1 - (1 - i / steps) ** 2
        jx = random.uniform(-1, 1) if i < steps else 0
        jy = random.uniform(-1, 1) if i < steps else 0
        new_x = current_x + (target_x - current_x) * t + jx
        new_y = current_y + (target_y - current_y) * t + jy
        pyautogui.moveTo(int(new_x), int(new_y), duration=0)
        time.sleep(duration / steps)


def human_click_at(x: int, y: int, move_duration: float | None = None) -> None:
    """Move mouse humanly then click."""
    assert pyautogui is not None
    human_move_mouse(x, y, move_duration)
    time.sleep(random.uniform(0.05, 0.15))
    pyautogui.click()
    time.sleep(random.uniform(0.1, 0.3))


def make_response(
    success: bool, data: dict | None = None, error: str | None = None
) -> dict:
    """Build response dict."""
    resp: dict = {"success": success, "timestamp": time.time()}
    if data:
        resp["data"] = data
    if error:
        resp["error"] = error
    return resp


async def handle_command(request: web.Request) -> web.Response:
    """POST / - Execute a command."""
    global WINDOW_OFFSET

    try:
        cmd = await request.json()
    except Exception as e:
        log(f"ERROR: Invalid JSON: {e}")
        return web.json_response(make_response(False, error=f"Invalid JSON: {e}"))

    action = cmd.get("action", "")
    params = {k: v for k, v in cmd.items() if k != "action"}
    log_request(action, params if params else None)

    # Actions that don't need page
    if action == "ping":
        url = browser.state.url if browser else ""
        log_response(True, "pong")
        return web.json_response(make_response(True, {"message": "pong", "url": url}))

    if action == "close":
        log("Shutting down...")
        asyncio.get_event_loop().call_soon(lambda: sys.exit(0))
        return web.json_response(make_response(True, {"message": "closing"}))

    # All other actions need a page
    page = get_active_page()
    if not page:
        log("ERROR: No active page")
        return web.json_response(make_response(False, error="No active page"))

    try:
        if action == "screenshot":
            full_page = cmd.get("full_page", False)
            data = await page.screenshot(type="png", full_page=full_page)
            b64 = base64.b64encode(data).decode()
            return web.json_response(
                make_response(
                    True,
                    {
                        "screenshot_b64": b64,
                        "url": page.url,
                        "title": await page.title(),
                    },
                )
            )

        if action == "goto":
            url = cmd.get("url", "")
            if not url:
                return web.json_response(make_response(False, error="No URL"))
            await page.goto(url, wait_until=cmd.get("wait_until", "domcontentloaded"))
            return web.json_response(
                make_response(True, {"url": page.url, "title": await page.title()})
            )

        if action == "click":
            selector = cmd.get("selector", "")
            if not selector:
                return web.json_response(make_response(False, error="No selector"))
            await page.click(selector)
            await asyncio.sleep(0.5)
            return web.json_response(make_response(True, {"clicked": selector}))

        if action == "mouse_move":
            x, y = cmd.get("x"), cmd.get("y")
            if x is None or y is None:
                return web.json_response(make_response(False, error="x,y required"))
            human_move_mouse(int(x), int(y), cmd.get("duration"))
            return web.json_response(
                make_response(True, {"moved_to": {"x": x, "y": y}})
            )

        if action == "mouse_click":
            assert pyautogui is not None
            x, y = cmd.get("x"), cmd.get("y")
            if x is None or y is None:
                pyautogui.click()
                return web.json_response(make_response(True, {"clicked_at": "current"}))
            sx, sy = screen_coords(int(x), int(y))
            pyautogui.click(sx, sy)
            return web.json_response(
                make_response(True, {"clicked_at": {"x": x, "y": y}})
            )

        if action == "human_click":
            x, y = cmd.get("x"), cmd.get("y")
            if x is None or y is None:
                return web.json_response(make_response(False, error="x,y required"))
            human_click_at(int(x), int(y), cmd.get("duration"))
            await asyncio.sleep(0.3)
            return web.json_response(
                make_response(True, {"human_clicked": {"x": x, "y": y}})
            )

        if action == "scroll":
            assert pyautogui is not None
            amount = cmd.get("amount", -3)
            x, y = cmd.get("x"), cmd.get("y")
            if x is not None and y is not None:
                human_move_mouse(int(x), int(y))
            pyautogui.scroll(int(amount))
            return web.json_response(make_response(True, {"scrolled": amount}))

        if action == "calibrate":
            WINDOW_OFFSET = await get_window_offset_js(page)
            return web.json_response(
                make_response(True, {"window_offset": WINDOW_OFFSET})
            )

        if action == "human_type":
            assert pyautogui is not None
            text = cmd.get("text", "")
            interval = cmd.get("interval", 0.08)
            if not text:
                return web.json_response(make_response(False, error="No text"))
            for char in text:
                if len(char) == 1:
                    pyautogui.press(char)
                else:
                    pyautogui.typewrite(char)
                time.sleep(max(0.02, interval + random.uniform(-0.03, 0.05)))
            return web.json_response(make_response(True, {"typed_len": len(text)}))

        if action == "fill":
            selector, value = cmd.get("selector", ""), cmd.get("value", "")
            await page.fill(selector, value)
            return web.json_response(make_response(True, {"filled": selector}))

        if action == "type":
            selector = cmd.get("selector", "")
            text = cmd.get("text", "")
            delay = cmd.get("delay", 0.05)
            await page.type(selector, text, delay=int(delay * 1000))
            return web.json_response(make_response(True, {"typed": selector}))

        if action == "eval":
            expr = cmd.get("expression", "")
            result = await page.evaluate(expr)
            return web.json_response(make_response(True, {"result": result}))

        if action == "get_interactive_elements":
            assert browser is not None
            visible_only = cmd.get("visible_only", True)
            browser._page = page
            elements = await browser.get_interactive_elements(visible_only)
            return web.json_response(
                make_response(True, {"count": len(elements), "elements": elements})
            )

        if action == "get_text":
            text = await page.inner_text("body")
            return web.json_response(
                make_response(True, {"text": text[:10000], "length": len(text)})
            )

        if action == "get_html":
            html = await page.content()
            return web.json_response(
                make_response(True, {"html": html, "length": len(html)})
            )

        return web.json_response(
            make_response(False, error=f"Unknown action: {action}")
        )

    except Exception as e:
        return web.json_response(make_response(False, error=str(e)))


async def handle_screenshot(_request: web.Request) -> web.Response:
    """GET /screenshot - Return PNG screenshot."""
    page = get_active_page()
    if not page:
        return web.Response(status=503, text="No active page")

    try:
        data = await page.screenshot(type="png")
        return web.Response(body=data, content_type="image/png")
    except Exception as e:
        return web.Response(status=500, text=str(e))


async def handle_state(_request: web.Request) -> web.Response:
    """GET /state - Return browser state."""
    if not browser:
        return web.json_response({"status": "not_ready"})

    page = get_active_page()
    return web.json_response(
        {
            "status": "ready" if page else "no_page",
            "url": browser.state.url,
            "title": browser.state.title,
            "window_offset": WINDOW_OFFSET,
        }
    )


async def handle_health(_request: web.Request) -> web.Response:
    """GET /health - Health check."""
    return web.Response(text="ok")


async def run_server(app: web.Application) -> None:
    """Run the HTTP server."""
    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, "0.0.0.0", PORT)
    await site.start()
    log(f"API listening on port {PORT}")

    # Keep running until browser closes
    while browser and browser._context and browser._context.pages:
        await asyncio.sleep(1)

    log("Browser closed, shutting down")
    await runner.cleanup()


async def main() -> None:
    global browser, WINDOW_OFFSET

    # Get resolution from env
    xvfb_res = os.environ.get("XVFB_RESOLUTION", "1920x1080x24")
    res_parts = xvfb_res.split("x")
    width = int(res_parts[0]) if len(res_parts) > 0 else 1920
    height = int(res_parts[1]) if len(res_parts) > 1 else 1080

    config = BrowserConfig(
        user_data_dir="/userdata",
        headless=False,
        with_extensions=True,
        width=width,
        height=height,
    )

    log(f"Starting browser at {width}x{height}")

    # Setup HTTP routes
    app = web.Application()
    app.router.add_post("/", handle_command)
    app.router.add_get("/screenshot", handle_screenshot)
    app.router.add_get("/state", handle_state)
    app.router.add_get("/health", handle_health)

    async with Browser(config) as b:
        browser = b
        if URL:
            log(f"Opening {URL}")
            await browser.goto(URL, wait_until="domcontentloaded")
        else:
            await browser._get_page()

        init_pyautogui()
        log("PyAutoGUI ready")

        await asyncio.sleep(1)
        page = get_active_page()
        if page:
            WINDOW_OFFSET = await get_window_offset_js(page)
        log(f"Window offset: {WINDOW_OFFSET}")

        log("Browser ready")

        await run_server(app)

    log("Done")


if __name__ == "__main__":
    asyncio.run(main())
