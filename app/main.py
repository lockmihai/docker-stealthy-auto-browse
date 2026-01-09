#!/usr/bin/env python3
"""
Interactive browser session with HTTP command interface.

Supports both Playwright (JS) clicks and PyAutoGUI (OS-level) clicks.
PyAutoGUI clicks are undetectable by behavioral analysis.

Endpoints:
    POST /                  - Execute command, returns JSON result
    GET /screenshot/browser - Get browser viewport screenshot as PNG
    GET /screenshot/desktop - Get full desktop screenshot as PNG
    GET /state              - Get browser state as JSON
    GET /health             - Health check
"""

from __future__ import annotations

import asyncio
import os
import subprocess
import sys
import tempfile
import time
from datetime import datetime

from aiohttp import web
from browser import Browser, BrowserConfig
from system import System

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

# System-level input (pyautogui)
system = System()

# Global browser instance
browser: Browser | None = None

PORT = 8080
URL = sys.argv[1] if len(sys.argv) > 1 else None


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
            system.move_mouse(int(x), int(y), cmd.get("duration"))
            return web.json_response(
                make_response(True, {"moved_to": {"x": x, "y": y}})
            )

        if action == "mouse_click":
            x, y = cmd.get("x"), cmd.get("y")
            system.click(int(x) if x else None, int(y) if y else None)
            if x is None or y is None:
                return web.json_response(make_response(True, {"clicked_at": "current"}))
            return web.json_response(
                make_response(True, {"clicked_at": {"x": x, "y": y}})
            )

        if action == "human_click":
            x, y = cmd.get("x"), cmd.get("y")
            if x is None or y is None:
                return web.json_response(make_response(False, error="x,y required"))
            system.move_mouse(int(x), int(y), cmd.get("duration"))
            system.click()
            return web.json_response(
                make_response(True, {"human_clicked": {"x": x, "y": y}})
            )

        if action == "scroll":
            amount = cmd.get("amount", -3)
            x, y = cmd.get("x"), cmd.get("y")
            system.scroll(
                int(amount),
                int(x) if x is not None else None,
                int(y) if y is not None else None,
            )
            return web.json_response(make_response(True, {"scrolled": amount}))

        if action == "calibrate":
            system.window_offset = await get_window_offset_js(page)
            return web.json_response(
                make_response(True, {"window_offset": system.window_offset})
            )

        if action == "set_viewport":
            width = cmd.get("width")
            height = cmd.get("height")
            if width is None or height is None:
                return web.json_response(
                    make_response(False, error="width and height required")
                )
            assert browser is not None
            result = browser.set_viewport(int(width), int(height))
            return web.json_response(make_response(True, result))

        if action == "reset_viewport":
            assert browser is not None
            result = browser.reset_viewport()
            return web.json_response(make_response(True, result))

        if action == "get_viewport":
            assert browser is not None
            result = browser.get_viewport()
            return web.json_response(make_response(True, result))

        if action == "human_type":
            text = cmd.get("text", "")
            interval = cmd.get("interval", 0.08)
            if not text:
                return web.json_response(make_response(False, error="No text"))
            system.human_type(text, interval)
            return web.json_response(make_response(True, {"typed_len": len(text)}))

        if action == "send_key":
            key = cmd.get("key", "")
            if not key:
                return web.json_response(make_response(False, error="No key"))
            system.send_key(key)
            return web.json_response(make_response(True, {"send_key": key}))

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


async def handle_screenshot_browser(_request: web.Request) -> web.Response:
    """GET /screenshot/browser - Return browser viewport PNG screenshot."""
    page = get_active_page()
    if not page:
        return web.Response(status=503, text="No active page")

    try:
        data = await page.screenshot(type="png")
        return web.Response(body=data, content_type="image/png")
    except Exception as e:
        return web.Response(status=500, text=str(e))


async def handle_screenshot_desktop(_request: web.Request) -> web.Response:
    """GET /screenshot/desktop - Return full desktop PNG screenshot using scrot."""
    try:
        with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as f:
            tmp_path = f.name

        result = subprocess.run(
            ["scrot", "-o", tmp_path],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            return web.Response(status=500, text=f"scrot failed: {result.stderr}")

        with open(tmp_path, "rb") as f:
            data = f.read()

        os.unlink(tmp_path)
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
            "window_offset": system.window_offset,
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
    global browser

    config = BrowserConfig(
        user_data_dir="/userdata",
    )

    log("Starting browser")

    # Setup HTTP routes
    app = web.Application()
    app.router.add_post("/", handle_command)
    app.router.add_get("/screenshot/browser", handle_screenshot_browser)
    app.router.add_get("/screenshot/desktop", handle_screenshot_desktop)
    app.router.add_get("/state", handle_state)
    app.router.add_get("/health", handle_health)

    async with Browser(config) as b:
        browser = b
        if URL:
            log(f"Opening {URL}")
            await browser.goto(URL, wait_until="domcontentloaded")
        else:
            await browser._get_page()

        system.init()
        log("PyAutoGUI ready")

        await asyncio.sleep(1)
        page = get_active_page()
        if page:
            system.window_offset = await get_window_offset_js(page)
        log(f"Window offset: {system.window_offset}")

        log("Browser ready")

        await run_server(app)

    log("Done")


if __name__ == "__main__":
    asyncio.run(main())
