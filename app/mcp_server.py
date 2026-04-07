"""MCP server for browser automation via Streamable HTTP transport.

Exposes browser actions as MCP tools so AI agents can drive the browser
over the Model Context Protocol. Mounted at /mcp on the main HTTP server.
"""

from __future__ import annotations

import asyncio
import json
from typing import Any, Callable, Coroutine

from fastmcp import FastMCP
from fastmcp.tools import ToolResult
from fastmcp.utilities.types import Image
from logger import get_logger
from mcp.types import TextContent

log = get_logger(__name__)

mcp = FastMCP(
    "stealthy-auto-browse",
    instructions=(
        "Stealth browser automation in Docker. Camoufox (custom Firefox) with "
        "zero Chrome DevTools Protocol exposure and real OS-level mouse/keyboard "
        "input via PyAutoGUI — undetectable by bot detection. "
        "Use system_click/system_type/send_key for stealth interactions. "
        "Use get_interactive_elements to find clickable elements with coordinates. "
        "Use run_script to execute multi-step workflows atomically. "
        "Passes Cloudflare, CreepJS, BrowserScan, Pixelscan, and all major bot detectors."
    ),
)

_dispatch: Callable[[dict], Coroutine[Any, Any, dict]] | None = None
_lock: asyncio.Lock | None = None


def set_dispatcher(
    fn: Callable[[dict], Coroutine[Any, Any, dict]],
    lock: asyncio.Lock | None = None,
) -> None:
    """Register the dispatch_action function and request lock from main.py."""
    global _dispatch, _lock
    _dispatch = fn
    _lock = lock


async def _call(action: str, **params: Any) -> dict:
    """Call dispatch_action with an action and params."""
    if not _dispatch:
        return {"success": False, "error": "Browser not ready"}
    filtered = {k: v for k, v in params.items() if v is not None}
    log.info(">> %s %s", action, filtered if filtered else "")
    cmd: dict[str, Any] = {"action": action}
    cmd.update(filtered)
    if _lock:
        async with _lock:
            result = await _dispatch(cmd)
    else:
        result = await _dispatch(cmd)
    if result.get("success", False):
        log.info("<< %s OK", action)
    else:
        log.warning("<< %s FAIL: %s", action, result.get("error", "?"))
    return result


def _text_result(result: dict) -> str:
    """Convert dispatch_action result to text for MCP response."""
    r = {k: v for k, v in result.items() if k != "_binary"}
    return json.dumps(r, default=str)


# =========================================================================
# Navigation
# =========================================================================


@mcp.tool
async def goto(
    url: str,
    wait_until: str = "domcontentloaded",
    referer: str | None = None,
) -> str:
    """Navigate the browser to a URL.

    Args:
        url: The URL to navigate to.
        wait_until: When to consider navigation done.
            "domcontentloaded" (default), "load", or "networkidle".
        referer: Optional HTTP Referer header value.
    """
    return _text_result(
        await _call("goto", url=url, wait_until=wait_until, referer=referer)
    )


@mcp.tool
async def get_text() -> str:
    """Get all visible text content from the current page (truncated to 10,000 chars)."""
    return _text_result(await _call("get_text"))


@mcp.tool
async def get_html() -> str:
    """Get the full HTML source of the current page."""
    return _text_result(await _call("get_html"))


@mcp.tool
async def get_interactive_elements(visible_only: bool = True) -> str:
    """Find all interactive elements on the page (buttons, links, inputs, etc.).

    Returns each element's viewport coordinates (x, y), dimensions,
    text content, and CSS selector. Use the coordinates with system_click.

    Args:
        visible_only: Only return elements visible in the viewport.
    """
    return _text_result(
        await _call("get_interactive_elements", visible_only=visible_only)
    )


# =========================================================================
# Screenshots
# =========================================================================


@mcp.tool
async def screenshot(
    screenshot_type: str = "browser",
    width: int | None = None,
    height: int | None = None,
    whLargest: int | None = None,
) -> ToolResult:
    """Take a screenshot of the browser viewport or full desktop.

    Args:
        screenshot_type: "browser" for page viewport, "desktop" for full virtual screen.
        width: Resize to this width (keeps aspect ratio if height omitted).
        height: Resize to this height (keeps aspect ratio if width omitted).
        whLargest: Resize so the largest dimension is this many pixels.
    """
    result = await _call(
        "save_screenshot",
        type=screenshot_type,
        width=width,
        height=height,
        whLargest=whLargest,
    )
    binary = result.pop("_binary", None)
    if binary:
        img = Image(data=binary, format="png")
        return ToolResult(content=[img])
    return ToolResult(content=[TextContent(type="text", text=_text_result(result))])


# =========================================================================
# System input (OS-level, undetectable)
# =========================================================================


@mcp.tool
async def system_click(x: int, y: int, duration: float | None = None) -> str:
    """Click at viewport coordinates with a human-like mouse movement.

    The mouse moves along a curved path with random jitter before clicking.
    Completely undetectable by bot detection. Get coordinates from
    get_interactive_elements.

    Args:
        x: Viewport X coordinate.
        y: Viewport Y coordinate.
        duration: Mouse movement time in seconds (random 0.2-0.6 if omitted).
    """
    return _text_result(await _call("system_click", x=x, y=y, duration=duration))


@mcp.tool
async def system_type(text: str, interval: float = 0.08) -> str:
    """Type text with real OS-level keystrokes (undetectable).

    Each keystroke has a randomized delay to mimic human typing.
    You must focus an input field first (e.g. with system_click).

    Args:
        text: The text to type.
        interval: Average delay between keystrokes in seconds.
    """
    return _text_result(await _call("system_type", text=text, interval=interval))


@mcp.tool
async def send_key(key: str) -> str:
    """Send a keyboard key or combo.

    Examples: "enter", "tab", "escape", "backspace", "ctrl+a", "ctrl+shift+t".

    Args:
        key: Key name or combo using PyAutoGUI key names.
    """
    return _text_result(await _call("send_key", key=key))


@mcp.tool
async def mouse_move(x: int, y: int, duration: float | None = None) -> str:
    """Move the mouse to viewport coordinates with human-like movement (no click).

    Use to hover over elements (trigger dropdowns, tooltips).

    Args:
        x: Viewport X coordinate.
        y: Viewport Y coordinate.
        duration: Movement time in seconds.
    """
    return _text_result(await _call("mouse_move", x=x, y=y, duration=duration))


@mcp.tool
async def scroll(amount: int = -3, x: int | None = None, y: int | None = None) -> str:
    """Scroll using the mouse wheel.

    Args:
        amount: Scroll amount. Negative = scroll down, positive = scroll up.
        x: Optional X coordinate to move mouse to before scrolling.
        y: Optional Y coordinate to move mouse to before scrolling.
    """
    return _text_result(await _call("scroll", amount=amount, x=x, y=y))


# =========================================================================
# Playwright input (selector-based, detectable)
# =========================================================================


@mcp.tool
async def click(selector: str) -> str:
    """Click an element by CSS selector or XPath.

    Faster than system_click but uses DOM event injection (detectable).
    XPath example: "xpath=//button[@id='submit']".

    Args:
        selector: CSS selector or XPath (prefix with "xpath=").
    """
    return _text_result(await _call("click", selector=selector))


@mcp.tool
async def fill(selector: str, value: str) -> str:
    """Set an input field's value instantly by CSS selector.

    Clears existing content first. Does not generate individual keystrokes.

    Args:
        selector: CSS selector of the input element.
        value: The value to set.
    """
    return _text_result(await _call("fill", selector=selector, value=value))


# =========================================================================
# JavaScript
# =========================================================================


@mcp.tool
async def eval_js(expression: str) -> str:
    """Execute JavaScript in the page context and return the result.

    Examples: "document.title", "document.querySelectorAll('a').length".

    Args:
        expression: JavaScript expression to evaluate.
    """
    return _text_result(await _call("eval", expression=expression))


# =========================================================================
# Wait conditions
# =========================================================================


@mcp.tool
async def wait_for_element(
    selector: str, state: str = "visible", timeout: float = 30
) -> str:
    """Wait for an element to reach a state.

    Args:
        selector: CSS selector or XPath.
        state: "visible" (default), "hidden", "attached", or "detached".
        timeout: Max wait time in seconds.
    """
    return _text_result(
        await _call("wait_for_element", selector=selector, state=state, timeout=timeout)
    )


@mcp.tool
async def wait_for_text(text: str, timeout: float = 30) -> str:
    """Wait for specific text to appear anywhere on the page.

    Args:
        text: Substring to wait for.
        timeout: Max wait time in seconds.
    """
    return _text_result(await _call("wait_for_text", text=text, timeout=timeout))


# =========================================================================
# Generic fallback for all other actions
# =========================================================================


@mcp.tool
async def browser_action(action: str, params: dict | None = None) -> str:
    """Execute any browser action not covered by the other tools.

    Useful for: cookies (get_cookies, set_cookie, delete_cookies),
    tabs (list_tabs, new_tab, switch_tab, close_tab),
    storage (get_storage, set_storage, clear_storage),
    dialogs (handle_dialog, get_last_dialog),
    downloads (get_last_download, upload_file),
    network logging (enable_network_log, get_network_log, etc.),
    console logging (enable_console_log, get_console_log, etc.),
    display (calibrate, get_resolution, enter_fullscreen, exit_fullscreen),
    scrolling (scroll_to_bottom, scroll_to_bottom_humanized),
    navigation (refresh), wait (wait_for_url, wait_for_network_idle),
    utility (ping, sleep).

    Args:
        action: The action name (e.g. "get_cookies", "set_cookie").
        params: Optional dict of action parameters.
    """
    p = params or {}
    return _text_result(await _call(action, **p))


@mcp.tool
async def run_script(
    steps: list[dict],
    name: str = "mcp_script",
    on_error: str = "stop",
) -> str:
    """Run multiple browser actions as a single atomic script.

    Each step is an action dict like {"action": "goto", "url": "..."}.
    Steps with "output_id" collect their results in the outputs dict.
    All steps run sequentially under a single request lock.

    Example steps:
        [
            {"action": "goto", "url": "https://example.com", "wait_until": "domcontentloaded"},
            {"action": "sleep", "duration": 2},
            {"action": "get_text", "output_id": "page_text"},
            {"action": "get_html", "output_id": "page_html"}
        ]

    Args:
        steps: List of action dicts to execute sequentially.
        name: Optional script name for logging.
        on_error: "stop" (default) to halt on first failure, "continue" to keep going.
    """
    return _text_result(
        await _call("run_script", steps=steps, name=name, on_error=on_error)
    )
