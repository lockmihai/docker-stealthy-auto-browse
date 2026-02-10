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
import io
import os
import random
import subprocess
import sys
import tempfile
import time
from datetime import datetime
from typing import Any

from aiohttp import web
from browser import Browser, BrowserConfig
from PIL import Image
from system import System

from loaders import Loader, find_loader, load_loaders, substitute_url

# =============================================================================
# CONTENT TYPES
# =============================================================================

CONTENT_TYPE_IMAGE_PNG = "image/png"
CONTENT_TYPE_TEXT_PLAIN = "text/plain"

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

# Loaded page loaders
loaders: list[Loader] = []

# Dialog handling state
_last_dialog: dict | None = None
_next_dialog_action: dict | None = None

# Maps dialog type to available buttons
_DIALOG_BUTTONS: dict[str, list[str]] = {
    "alert": ["ok"],
    "confirm": ["ok", "cancel"],
    "prompt": ["ok", "cancel"],
    "beforeunload": ["leave", "stay"],
}

# Tab management
_active_page: Any = None

# Download tracking
_last_download: dict | None = None

# Network logging
_network_log: list[dict] = []
_network_logging: bool = False
_network_handler_pages: set[int] = set()

PORT = 8080
URL = sys.argv[1] if len(sys.argv) > 1 else None


async def _on_dialog(dialog: Any) -> None:
    """Handle browser dialogs (alert/confirm/prompt/beforeunload)."""
    global _last_dialog, _next_dialog_action

    _last_dialog = {
        "type": dialog.type,
        "message": dialog.message,
        "default_value": dialog.default_value,
        "buttons": _DIALOG_BUTTONS.get(dialog.type, ["ok"]),
    }
    log(f"Dialog [{dialog.type}]: {dialog.message}")

    action = _next_dialog_action
    _next_dialog_action = None

    if action and not action.get("accept", True):
        await dialog.dismiss()
        return

    prompt_text = action.get("text") if action else None
    if prompt_text is not None:
        await dialog.accept(prompt_text)
        return

    await dialog.accept()


async def _on_download(download: Any) -> None:
    """Track file downloads."""
    global _last_download
    try:
        path = await download.path()
        _last_download = {
            "url": download.url,
            "filename": download.suggested_filename,
            "path": str(path) if path else None,
        }
    except Exception:
        _last_download = {
            "url": download.url,
            "filename": download.suggested_filename,
            "path": None,
        }
    log(f"Download: {download.suggested_filename}")


def _on_request(request: Any) -> None:
    """Track network requests when logging is enabled."""
    if not _network_logging:
        return
    _network_log.append(
        {
            "type": "request",
            "url": request.url,
            "method": request.method,
            "resource_type": request.resource_type,
            "timestamp": time.time(),
        }
    )


def _on_response(response: Any) -> None:
    """Track network responses when logging is enabled."""
    if not _network_logging:
        return
    _network_log.append(
        {
            "type": "response",
            "url": response.url,
            "status": response.status,
            "timestamp": time.time(),
        }
    )


def _setup_page_handlers(page: Any) -> None:
    """Register all event handlers on a page."""
    page.on("dialog", _on_dialog)
    page.on("download", _on_download)
    page_id = id(page)
    if page_id not in _network_handler_pages:
        page.on("request", _on_request)
        page.on("response", _on_response)
        _network_handler_pages.add(page_id)


def get_active_page() -> Any:
    """Get the currently active page."""
    global _active_page
    if not browser or not browser._context:
        return None
    pages = browser._context.pages
    if not pages:
        _active_page = None
        return None
    if _active_page is None or _active_page not in pages:
        _active_page = pages[-1]
    return _active_page


async def get_window_offset_js(page) -> dict:
    """Get browser content area offset from screen origin.

    Uses Firefox's mozInnerScreenX/Y which report the real screen position
    of the viewport. These are NOT spoofed by Camoufox (unlike outerHeight/
    innerHeight which are fingerprint-spoofed and give wrong offsets).
    """
    try:
        return await page.evaluate(
            """() => ({
                x: Math.round(window.mozInnerScreenX),
                y: Math.round(window.mozInnerScreenY)
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


# =============================================================================
# ACTION DISPATCH
# =============================================================================


async def dispatch_action(cmd: dict) -> dict:
    """Execute a single action command. Returns response dict."""
    global _next_dialog_action, _active_page, _network_logging
    action = cmd.get("action", "")

    # Actions that don't need page
    if action == "ping":
        url = browser.state.url if browser else ""
        return make_response(True, {"message": "pong", "url": url})

    if action == "close":
        log("Shutting down...")
        asyncio.get_event_loop().call_soon(lambda: sys.exit(0))
        return make_response(True, {"message": "closing"})

    if action == "sleep":
        duration = cmd.get("duration", 1)
        await asyncio.sleep(float(duration))
        return make_response(True, {"slept": duration})

    if action == "handle_dialog":
        _next_dialog_action = {
            "accept": cmd.get("accept", True),
            "text": cmd.get("text"),
        }
        return make_response(True, {"configured": _next_dialog_action})

    if action == "get_last_dialog":
        if not _last_dialog:
            return make_response(True, {"dialog": None})
        return make_response(True, {"dialog": _last_dialog})

    # --- Tab management ---

    if action == "list_tabs":
        pages = browser._context.pages if browser and browser._context else []
        tabs = []
        active = get_active_page()
        for i, p in enumerate(pages):
            tabs.append({"index": i, "url": p.url, "active": p is active})
        return make_response(True, {"tabs": tabs, "count": len(tabs)})

    if action == "new_tab":
        if not browser or not browser._context:
            return make_response(False, error="No browser context")
        new_page = await browser._context.new_page()
        _setup_page_handlers(new_page)
        _active_page = new_page
        tab_url: str | None = cmd.get("url")
        if tab_url:
            await new_page.goto(
                tab_url, wait_until=cmd.get("wait_until", "domcontentloaded")
            )
        return make_response(
            True,
            {
                "index": len(browser._context.pages) - 1,
                "url": new_page.url,
            },
        )

    if action == "switch_tab":
        index = cmd.get("index")
        if index is None:
            return make_response(False, error="index required")
        pages = browser._context.pages if browser and browser._context else []
        if index < 0 or index >= len(pages):
            return make_response(False, error=f"Invalid tab index: {index}")
        _active_page = pages[index]
        return make_response(True, {"index": index, "url": _active_page.url})

    if action == "close_tab":
        index = cmd.get("index")
        pages = browser._context.pages if browser and browser._context else []
        if not pages:
            return make_response(False, error="No tabs open")
        if index is not None:
            if index < 0 or index >= len(pages):
                return make_response(False, error=f"Invalid tab index: {index}")
            target = pages[index]
        else:
            target = get_active_page() or pages[-1]
        await target.close()
        pages = browser._context.pages if browser and browser._context else []
        _active_page = pages[-1] if pages else None
        return make_response(True, {"closed": True, "remaining": len(pages)})

    # --- Cookie management ---

    if action == "get_cookies":
        if not browser or not browser._context:
            return make_response(False, error="No browser context")
        urls = cmd.get("urls")
        if urls:
            cookies = await browser._context.cookies(urls)
        else:
            cookies = await browser._context.cookies()
        return make_response(True, {"cookies": cookies, "count": len(cookies)})

    if action == "set_cookie":
        if not browser or not browser._context:
            return make_response(False, error="No browser context")
        cookie = {k: v for k, v in cmd.items() if k != "action"}
        await browser._context.add_cookies([cookie])
        return make_response(True, {"set": cookie.get("name")})

    if action == "delete_cookies":
        if not browser or not browser._context:
            return make_response(False, error="No browser context")
        await browser._context.clear_cookies()
        return make_response(True, {"cleared": True})

    # --- Download tracking ---

    if action == "get_last_download":
        return make_response(True, {"download": _last_download})

    # --- Network logging ---

    if action == "enable_network_log":
        _network_logging = True
        page = get_active_page()
        if page:
            _setup_page_handlers(page)
        return make_response(True, {"enabled": True})

    if action == "disable_network_log":
        _network_logging = False
        return make_response(True, {"enabled": False})

    if action == "get_network_log":
        return make_response(
            True, {"log": list(_network_log), "count": len(_network_log)}
        )

    if action == "clear_network_log":
        _network_log.clear()
        return make_response(True, {"cleared": True})

    # All other actions need a page
    page = get_active_page()
    if not page:
        return make_response(False, error="No active page")

    if action == "goto":
        url = cmd.get("url", "")
        if not url:
            return make_response(False, error="No URL")

        # Check for matching loader (but not when called from execute_loader
        # to avoid infinite recursion)
        if not cmd.get("_from_loader"):
            loader = find_loader(loaders, url)
            if loader:
                log(f"Loader matched: {loader.name}")
                return await execute_loader(loader, url)

        await page.goto(url, wait_until=cmd.get("wait_until", "domcontentloaded"))
        return make_response(True, {"url": page.url, "title": await page.title()})

    if action == "back":
        await page.go_back(wait_until=cmd.get("wait_until", "domcontentloaded"))
        return make_response(True, {"url": page.url, "title": await page.title()})

    if action == "forward":
        await page.go_forward(wait_until=cmd.get("wait_until", "domcontentloaded"))
        return make_response(True, {"url": page.url, "title": await page.title()})

    if action == "refresh":
        await page.reload(wait_until=cmd.get("wait_until", "domcontentloaded"))
        return make_response(True, {"url": page.url, "title": await page.title()})

    if action == "click":
        selector = cmd.get("selector", "")
        if not selector:
            return make_response(False, error="No selector")
        await page.click(selector)
        await asyncio.sleep(0.5)
        return make_response(True, {"clicked": selector})

    if action == "mouse_move":
        x, y = cmd.get("x"), cmd.get("y")
        if x is None or y is None:
            return make_response(False, error="x,y required")
        system.move_mouse(int(x), int(y), cmd.get("duration"))
        return make_response(True, {"moved_to": {"x": x, "y": y}})

    if action == "mouse_click":
        x, y = cmd.get("x"), cmd.get("y")
        system.click(int(x) if x else None, int(y) if y else None)
        if x is None or y is None:
            return make_response(True, {"clicked_at": "current"})
        return make_response(True, {"clicked_at": {"x": x, "y": y}})

    if action == "system_click":
        x, y = cmd.get("x"), cmd.get("y")
        if x is None or y is None:
            return make_response(False, error="x,y required")
        system.move_mouse(int(x), int(y), cmd.get("duration"))
        system.click()
        return make_response(True, {"system_clicked": {"x": x, "y": y}})

    if action == "scroll":
        amount = cmd.get("amount", -3)
        x, y = cmd.get("x"), cmd.get("y")
        system.scroll(
            int(amount),
            int(x) if x is not None else None,
            int(y) if y is not None else None,
        )
        return make_response(True, {"scrolled": amount})

    if action == "scroll_to_bottom":
        delay = cmd.get("delay", 0.4)
        delay_ms = int(float(delay) * 1000)
        await page.evaluate(
            f"""(async () => {{
            let prev = -1;
            while (window.scrollY !== prev) {{
                prev = window.scrollY;
                window.scrollBy(0, window.innerHeight);
                await new Promise(r => setTimeout(r, {delay_ms}));
            }}
            window.scrollTo(0, 0);
        }})()"""
        )
        return make_response(True, {"scrolled": "bottom"})

    if action == "scroll_to_bottom_humanized":
        min_clicks = int(cmd.get("min_clicks", 2))
        max_clicks = int(cmd.get("max_clicks", 6))
        delay = float(cmd.get("delay", 0.5))
        while True:
            prev = await page.evaluate("window.scrollY")
            clicks = random.randint(min_clicks, max_clicks)
            system.scroll(-clicks)
            jittered = delay * random.uniform(0.7, 1.3)
            await asyncio.sleep(jittered)
            curr = await page.evaluate("window.scrollY")
            if curr == prev:
                break
        await page.evaluate("window.scrollTo(0, 0)")
        return make_response(True, {"scrolled": "bottom_humanized"})

    if action == "calibrate":
        system.window_offset = await get_window_offset_js(page)
        return make_response(True, {"window_offset": system.window_offset})

    if action == "enter_fullscreen":
        is_fullscreen = await page.evaluate("!!document.fullscreenElement")
        if not is_fullscreen:
            await page.evaluate("document.documentElement.requestFullscreen()")
        return make_response(True, {"fullscreen": True, "changed": not is_fullscreen})

    if action == "exit_fullscreen":
        is_fullscreen = await page.evaluate("!!document.fullscreenElement")
        if is_fullscreen:
            await page.evaluate("document.exitFullscreen()")
        return make_response(True, {"fullscreen": False, "changed": is_fullscreen})

    if action == "get_resolution":
        result = system.get_resolution()
        return make_response(True, result)

    if action == "system_type":
        text = cmd.get("text", "")
        interval = cmd.get("interval", 0.08)
        if not text:
            return make_response(False, error="No text")
        system.system_type(text, interval)
        return make_response(True, {"typed_len": len(text)})

    if action == "send_key":
        key = cmd.get("key", "")
        if not key:
            return make_response(False, error="No key")
        system.send_key(key)
        return make_response(True, {"send_key": key})

    if action == "fill":
        selector, value = cmd.get("selector", ""), cmd.get("value", "")
        await page.fill(selector, value)
        return make_response(True, {"filled": selector})

    if action == "type":
        selector = cmd.get("selector", "")
        text = cmd.get("text", "")
        delay = cmd.get("delay", 0.05)
        await page.type(selector, text, delay=int(delay * 1000))
        return make_response(True, {"typed": selector})

    if action == "eval":
        expr = cmd.get("expression", "")
        result = await page.evaluate(expr)
        return make_response(True, {"result": result})

    if action == "get_interactive_elements":
        assert browser is not None
        visible_only = cmd.get("visible_only", True)
        browser._page = page
        elements = await browser.get_interactive_elements(visible_only)
        return make_response(True, {"count": len(elements), "elements": elements})

    if action == "get_text":
        text = await page.inner_text("body")
        return make_response(True, {"text": text[:10000], "length": len(text)})

    if action == "get_html":
        html = await page.content()
        return make_response(True, {"html": html, "length": len(html)})

    # --- Wait conditions ---

    if action == "wait_for_element":
        selector = cmd.get("selector", "")
        if not selector:
            return make_response(False, error="selector required")
        state = cmd.get("state", "visible")
        timeout = cmd.get("timeout", 30)
        await page.wait_for_selector(
            selector, state=state, timeout=int(float(timeout) * 1000)
        )
        return make_response(True, {"selector": selector, "state": state})

    if action == "wait_for_text":
        text = cmd.get("text", "")
        if not text:
            return make_response(False, error="text required")
        timeout = cmd.get("timeout", 30)
        escaped = text.replace("\\", "\\\\").replace("'", "\\'")
        await page.wait_for_function(
            f"document.body.innerText.includes('{escaped}')",
            timeout=int(float(timeout) * 1000),
        )
        return make_response(True, {"text": text, "found": True})

    if action == "wait_for_url":
        pattern = cmd.get("url", "")
        if not pattern:
            return make_response(False, error="url required")
        timeout = cmd.get("timeout", 30)
        await page.wait_for_url(pattern, timeout=int(float(timeout) * 1000))
        return make_response(True, {"url": page.url})

    if action == "wait_for_network_idle":
        timeout = cmd.get("timeout", 30)
        await page.wait_for_load_state(
            "networkidle", timeout=int(float(timeout) * 1000)
        )
        return make_response(True, {"idle": True})

    # --- Storage management ---

    if action == "get_storage":
        storage_type = cmd.get("type", "local")
        if storage_type == "local":
            raw = await page.evaluate("JSON.stringify(localStorage)")
        else:
            raw = await page.evaluate("JSON.stringify(sessionStorage)")
        import json as _json

        items = _json.loads(raw) if raw else {}
        return make_response(True, {"items": items, "type": storage_type})

    if action == "set_storage":
        storage_type = cmd.get("type", "local")
        key = cmd.get("key", "")
        value = cmd.get("value", "")
        if not key:
            return make_response(False, error="key required")
        escaped_key = key.replace("\\", "\\\\").replace("'", "\\'")
        escaped_val = value.replace("\\", "\\\\").replace("'", "\\'")
        if storage_type == "local":
            await page.evaluate(
                f"localStorage.setItem('{escaped_key}', '{escaped_val}')"
            )
        else:
            await page.evaluate(
                f"sessionStorage.setItem('{escaped_key}', '{escaped_val}')"
            )
        return make_response(True, {"set": key, "type": storage_type})

    if action == "clear_storage":
        storage_type = cmd.get("type", "local")
        if storage_type == "local":
            await page.evaluate("localStorage.clear()")
        else:
            await page.evaluate("sessionStorage.clear()")
        return make_response(True, {"cleared": storage_type})

    # --- File upload ---

    if action == "upload_file":
        selector = cmd.get("selector", "")
        file_path = cmd.get("file_path", "")
        if not selector:
            return make_response(False, error="selector required")
        if not file_path:
            return make_response(False, error="file_path required")
        if not os.path.isfile(file_path):
            return make_response(False, error=f"File not found: {file_path}")
        await page.set_input_files(selector, file_path)
        return make_response(
            True,
            {
                "selector": selector,
                "file": os.path.basename(file_path),
                "size": os.path.getsize(file_path),
            },
        )

    return make_response(False, error=f"Unknown action: {action}")


# =============================================================================
# LOADER EXECUTION
# =============================================================================


async def execute_loader(loader: Loader, url: str) -> dict:
    """Execute a loader's steps, returning the final result."""
    results = []
    for step in loader.steps:
        step = substitute_url(step, url)
        # Mark goto steps from loaders to prevent infinite recursion
        if step.get("action") == "goto":
            step = {**step, "_from_loader": True}
        log(f"  [{loader.name}] {step.get('action', '?')}")
        result = await dispatch_action(step)
        results.append(result)
        if not result.get("success", True):
            log(f"  [{loader.name}] Step failed: {result.get('error')}")
            break
    return make_response(
        True,
        {
            "loader": loader.name,
            "steps_executed": len(results),
            "last_result": results[-1] if results else None,
        },
    )


# =============================================================================
# HTTP HANDLERS
# =============================================================================


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

    try:
        result = await dispatch_action(cmd)
        return web.json_response(result)
    except Exception as e:
        return web.json_response(make_response(False, error=str(e)))


def _resize_png(data: bytes, request: web.Request) -> bytes:
    """Resize PNG bytes based on query params: width, height, whLargest."""
    q = request.query
    w_str = q.get("width")
    h_str = q.get("height")
    largest_str = q.get("whLargest")

    if not w_str and not h_str and not largest_str:
        return data

    img = Image.open(io.BytesIO(data))
    orig_w, orig_h = img.size

    if largest_str:
        largest = int(largest_str)
        if orig_w >= orig_h:
            new_w = largest
            new_h = int(orig_h * largest / orig_w)
        else:
            new_h = largest
            new_w = int(orig_w * largest / orig_h)
    elif w_str and h_str:
        new_w = int(w_str)
        new_h = int(h_str)
    elif w_str:
        new_w = int(w_str)
        new_h = int(orig_h * new_w / orig_w)
    else:
        new_h = int(h_str)  # type: ignore[arg-type]
        new_w = int(orig_w * new_h / orig_h)

    img = img.resize((new_w, new_h), Image.LANCZOS)
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


async def handle_screenshot_browser(request: web.Request) -> web.Response:
    """GET /screenshot/browser - Return browser viewport PNG screenshot."""
    page = get_active_page()
    if not page:
        return web.Response(status=503, text="No active page")

    try:
        data = await page.screenshot(type="png")
        data = _resize_png(data, request)
        return web.Response(body=data, content_type=CONTENT_TYPE_IMAGE_PNG)
    except Exception as e:
        return web.Response(status=500, text=str(e))


async def handle_screenshot_desktop(request: web.Request) -> web.Response:
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
        data = _resize_png(data, request)
        return web.Response(body=data, content_type=CONTENT_TYPE_IMAGE_PNG)
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
    global browser, loaders

    config = BrowserConfig()

    # Load page loaders
    loaders_dir = os.environ.get("LOADERS_DIR", "/loaders")
    loaders = load_loaders(loaders_dir)
    if loaders:
        log(f"Loaded {len(loaders)} loader(s) from {loaders_dir}")

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
            _setup_page_handlers(page)
            system.window_offset = await get_window_offset_js(page)
        log(f"Window offset: {system.window_offset}")

        log("Browser ready")

        await run_server(app)

    log("Done")


if __name__ == "__main__":
    asyncio.run(main())
