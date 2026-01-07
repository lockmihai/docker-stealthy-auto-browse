"""Stealth browser module using patchright."""

from __future__ import annotations

import asyncio
import base64
import os
import shutil
import signal
import subprocess
import tempfile
from dataclasses import dataclass, field
from typing import Any

# Brave browser executable path
BROWSER_PATH = "/usr/bin/brave-browser"

# Path to JS files
_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))


class BrowserError(Exception):
    """Browser error."""


@dataclass
class BrowserState:
    """Current browser state."""

    url: str = ""
    title: str = ""
    content: str = ""
    screenshot_b64: str = ""


@dataclass
class BrowserConfig:
    """Browser configuration."""

    width: int = 1920
    height: int = 1080
    executable_path: str | None = BROWSER_PATH
    headless: bool = False  # False is stealthier
    user_data_dir: str | None = None  # None = temp dir
    use_xvfb: bool = True  # Start Xvfb if no DISPLAY
    xvfb_display: str = ":99"
    timeout: float = 30.0
    with_extensions: bool = False  # Enable extension installation from web store

    # Stealth args - always applied
    stealth_args: list[str] = field(
        default_factory=lambda: [
            "--disable-blink-features=AutomationControlled",
        ]
    )

    # Extra args
    extra_args: list[str] = field(default_factory=list)


class Browser:
    """Stealth browser using patchright."""

    def __init__(self, config: BrowserConfig | None = None) -> None:
        self.config = config or BrowserConfig()
        self._xvfb_proc: subprocess.Popen[bytes] | None = None
        self._playwright: Any = None
        self._context: Any = None
        self._page: Any = None
        self._temp_user_data_dir: str | None = None
        self._state = BrowserState()

    @property
    def state(self) -> BrowserState:
        """Current browser state."""
        return self._state

    @property
    def is_running(self) -> bool:
        """Check if browser is running."""
        return self._context is not None

    @property
    def page(self) -> Any:
        """Current page object for direct access."""
        return self._page

    async def start(self) -> None:
        """Start browser."""
        if self.is_running:
            return

        await self._setup_display()
        await self._launch_browser()

    async def stop(self) -> None:
        """Stop browser and cleanup."""
        if self._page:
            try:
                await self._page.close()
            except Exception:
                pass
            self._page = None

        if self._context:
            try:
                await self._context.close()
            except Exception:
                pass
            self._context = None

        if self._playwright:
            try:
                await self._playwright.stop()
            except Exception:
                pass
            self._playwright = None

        self._stop_xvfb()
        self._cleanup_temp_dir()
        self._state = BrowserState()

    async def goto(self, url: str, wait_until: str = "networkidle") -> BrowserState:
        """Navigate to URL and update state."""
        if not self.is_running:
            await self.start()

        page = await self._get_page()
        timeout_ms = int(self.config.timeout * 1000)

        await page.goto(url, timeout=timeout_ms, wait_until=wait_until)
        await self._update_state()
        return self._state

    async def screenshot(self, full_page: bool = False, quality: int = 80) -> str:
        """Take screenshot, return base64 string."""
        if not self._page:
            return ""

        try:
            data = await self._page.screenshot(
                type="jpeg",
                quality=quality,
                full_page=full_page,
            )
            b64 = base64.b64encode(data).decode()
            self._state.screenshot_b64 = b64
            return b64
        except Exception:
            return ""

    async def refresh(self) -> BrowserState:
        """Refresh current page."""
        if not self._page:
            return self._state

        await self._page.reload()
        await self._update_state()
        return self._state

    async def back(self) -> BrowserState:
        """Go back."""
        if not self._page:
            return self._state

        await self._page.go_back()
        await self._update_state()
        return self._state

    async def forward(self) -> BrowserState:
        """Go forward."""
        if not self._page:
            return self._state

        await self._page.go_forward()
        await self._update_state()
        return self._state

    async def click(self, selector: str) -> None:
        """Click element."""
        if not self._page:
            return

        await self._page.click(selector)
        await self._update_state()

    async def fill(self, selector: str, value: str) -> None:
        """Fill input field."""
        if not self._page:
            return

        await self._page.fill(selector, value)

    async def type(self, selector: str, text: str, delay: float = 0.05) -> None:
        """Type text with delay between keystrokes."""
        if not self._page:
            return

        await self._page.type(selector, text, delay=int(delay * 1000))

    async def wait_for(self, selector: str, state: str = "visible") -> None:
        """Wait for element."""
        if not self._page:
            return

        timeout_ms = int(self.config.timeout * 1000)
        await self._page.wait_for_selector(selector, state=state, timeout=timeout_ms)

    async def evaluate(self, expression: str) -> Any:
        """Evaluate JavaScript."""
        if not self._page:
            return None

        return await self._page.evaluate(expression)

    async def get_interactive_elements(self, visible_only: bool = True) -> list[dict]:
        """Get all interactive elements on the page.

        Returns list of element dicts with keys:
            i: index
            tag: HTML tag name
            id: element ID or None
            text: visible text content (truncated to 60 chars)
            selector: CSS selector or XPath
            x, y: center coordinates
            w, h: dimensions
            visible: whether in viewport
        """
        if not self._page:
            return []

        js_path = os.path.join(_SCRIPT_DIR, "get_elements.js")
        with open(js_path) as f:
            js_code = f.read()

        return await self._page.evaluate(js_code, visible_only)

    async def _setup_display(self) -> None:
        """Setup X display (Xvfb if needed)."""
        if os.environ.get("DISPLAY"):
            return

        if not self.config.use_xvfb:
            return

        xvfb = shutil.which("Xvfb")
        if not xvfb:
            raise BrowserError("Xvfb not found and no DISPLAY set")

        display = self.config.xvfb_display
        resolution = f"{self.config.width}x{self.config.height}x24"

        self._xvfb_proc = subprocess.Popen(
            [xvfb, display, "-screen", "0", resolution, "-ac", "+extension", "GLX"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        await asyncio.sleep(0.5)

        if self._xvfb_proc.poll() is not None:
            raise BrowserError("Xvfb failed to start")

        os.environ["DISPLAY"] = display

    def _stop_xvfb(self) -> None:
        """Stop Xvfb."""
        if not self._xvfb_proc:
            return

        try:
            self._xvfb_proc.send_signal(signal.SIGTERM)
            self._xvfb_proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self._xvfb_proc.kill()
        except Exception:
            pass

        self._xvfb_proc = None

    def _cleanup_temp_dir(self) -> None:
        """Cleanup temp user data dir."""
        if not self._temp_user_data_dir:
            return

        try:
            shutil.rmtree(self._temp_user_data_dir, ignore_errors=True)
        except Exception:
            pass

        self._temp_user_data_dir = None

    async def _launch_browser(self) -> None:
        """Launch browser via patchright."""
        from patchright.async_api import async_playwright

        if self.config.user_data_dir:
            user_data_dir = self.config.user_data_dir
        else:
            self._temp_user_data_dir = tempfile.mkdtemp(prefix="browser_")
            user_data_dir = self._temp_user_data_dir

        self._playwright = await async_playwright().start()

        args = list(self.config.stealth_args) + list(self.config.extra_args)

        # Add window size from XVFB_RESOLUTION
        xvfb_res = os.environ.get("XVFB_RESOLUTION", "1920x1080x24")
        parts = xvfb_res.split("x")
        if len(parts) >= 2:
            args.append(f"--window-size={parts[0]},{parts[1]}")
            args.append("--window-position=0,0")

        launch_opts: dict[str, Any] = {
            "user_data_dir": user_data_dir,
            "headless": self.config.headless,
            "no_viewport": True,  # Let browser size naturally from --start-maximized
            "chromium_sandbox": False,
            "args": args,
        }

        if self.config.with_extensions:
            launch_opts["ignore_default_args"] = [
                "--disable-extensions",
                "--disable-component-update",
            ]

        if self.config.executable_path:
            launch_opts["executable_path"] = self.config.executable_path

        try:
            self._context = await self._playwright.chromium.launch_persistent_context(
                **launch_opts
            )
        except Exception as e:
            await self.stop()
            raise BrowserError(f"Failed to launch browser: {e}")

    async def _get_page(self) -> Any:
        """Get or create page."""
        if self._page:
            return self._page

        # Reuse existing page from context if available
        pages = self._context.pages
        if pages:
            self._page = pages[0]
            return self._page

        self._page = await self._context.new_page()
        return self._page

    async def _update_state(self) -> None:
        """Update state from current page."""
        if not self._page:
            return

        try:
            self._state.url = self._page.url
            self._state.title = await self._page.title()
            self._state.content = await self._page.inner_text("body")
        except Exception:
            pass

    async def __aenter__(self) -> "Browser":
        """Async context manager entry."""
        await self.start()
        return self

    async def __aexit__(self, *args: Any) -> None:
        """Async context manager exit."""
        await self.stop()
