"""Redis-backed browser cookie sync.

Enables multiple browser instances to share cookies via Redis pubsub.
When a cookie changes, publishes to PubSub so other instances update.

Usage:
    REDIS_URL=redis://redis:6379 python main.py
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
from typing import Any

from redis.asyncio import from_url as redis_from_url

REDIS_URL = os.environ.get("REDIS_URL")
KEY_PREFIX = "SABROWSE:"
COOKIES_KEY = f"{KEY_PREFIX}COOKIES"
UPDATE_CHANNEL = f"{KEY_PREFIX}UPDATE"

logger = logging.getLogger("redis_sync")


class RedisSync:
    """Manages Redis-backed state sync for a browser instance."""

    def __init__(self):
        self._redis = None
        self._pubsub = None
        self._listen_task = None
        self._enabled = REDIS_URL is not None
        # In-memory cache: {(name, domain, path): cookie_dict}
        self._cookie_cache: dict[tuple[str, str, str], dict[str, Any]] = {}
        # Set by pubsub listener so get_cookies applies the clear to browser context
        self._pending_clear_cookies = False
        # Browser context for eager cookie application on PubSub receive
        self._context: Any = None

    @property
    def enabled(self) -> bool:
        return self._enabled

    async def set_context(self, context: Any) -> None:
        """Register browser context; applies cached cookies from Redis immediately."""
        self._context = context
        if context and self._cookie_cache:
            await self._apply_cache_to_context()

    def clear_context(self) -> None:
        """Clear context reference (called before stop to prevent apply to closed context)."""
        self._context = None

    async def start(self) -> None:
        """Start Redis connection, load existing cookies, and start PubSub listener."""
        if not self._enabled:
            return

        self._redis = redis_from_url(REDIS_URL, decode_responses=True)
        self._pubsub = self._redis.pubsub()
        await self._pubsub.subscribe(UPDATE_CHANNEL)
        self._listen_task = asyncio.create_task(self._listen_loop())

        existing = await self._redis.hgetall(COOKIES_KEY)
        for field, raw in existing.items():
            try:
                cookie = json.loads(raw)
                key = (
                    cookie.get("name", ""),
                    cookie.get("domain", ""),
                    cookie.get("path", ""),
                )
                if key and any(key):
                    self._cookie_cache[key] = cookie
            except Exception as e:
                logger.warning("Failed to parse stored cookie %s: %s", field, e)

        if self._cookie_cache:
            logger.info(
                "Loaded %d cookies from Redis on startup", len(self._cookie_cache)
            )

        logger.info("Redis sync started")

    async def stop(self) -> None:
        """Stop Redis connection and PubSub listener."""
        if self._listen_task:
            self._listen_task.cancel()
            try:
                await self._listen_task
            except asyncio.CancelledError:
                pass
            self._listen_task = None

        if self._pubsub:
            await self._pubsub.unsubscribe(UPDATE_CHANNEL)
            await self._pubsub.close()
            self._pubsub = None

        if self._redis:
            await self._redis.close()
            self._redis = None

    async def _apply_cache_to_context(self) -> None:
        """Apply all cookies in cache to the browser context."""
        if not self._context or not self._cookie_cache:
            return
        cookies = list(self._cookie_cache.values())
        try:
            await self._context.add_cookies(cookies)
            logger.info("Applied %d cached cookies to browser context", len(cookies))
        except Exception as e:
            logger.warning("Failed to apply cached cookies to context: %s", e)

    async def _listen_loop(self) -> None:
        """Listen for PubSub messages and merge updates."""
        while True:
            try:
                msg = await self._pubsub.get_message(timeout=10)
                if not msg:
                    continue
                if msg["type"] != "message":
                    continue

                data = json.loads(msg["data"])
                self._merge_update(data)
                await self._eager_apply(data)
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.warning("PubSub listener error: %s", e)

    async def _eager_apply(self, data: dict[str, Any]) -> None:
        """Eagerly apply a received PubSub update directly to the browser context."""
        if not self._context:
            return
        kind = data.get("kind")
        if kind == "cookie":
            cookie = data.get("cookie", {})
            if not cookie:
                return
            try:
                await self._context.add_cookies([cookie])
                logger.debug(
                    "Eagerly applied synced cookie: %s domain=%s",
                    cookie.get("name"),
                    cookie.get("domain"),
                )
            except Exception as e:
                logger.warning(
                    "Failed to eagerly apply cookie %s: %s", cookie.get("name"), e
                )
            return
        if kind == "clear_cookies":
            try:
                await self._context.clear_cookies()
                self._pending_clear_cookies = False
                logger.debug("Eagerly applied cookie clear")
            except Exception as e:
                logger.warning("Failed to eagerly clear cookies: %s", e)

    def _merge_update(self, data: dict[str, Any]) -> None:
        """Merge an incoming update into our cache."""
        kind = data.get("kind")
        if kind == "cookie":
            cookie = data.get("cookie", {})
            key = (
                cookie.get("name", ""),
                cookie.get("domain", ""),
                cookie.get("path", ""),
            )
            if key and any(key):
                # Update cache, newer cookie wins by creation time
                existing = self._cookie_cache.get(key, {})
                # Replace if new has newer creation time or we don't have it
                existing_creates = existing.get("creationTime", 0)
                new_creates = cookie.get("creationTime", 0)
                if new_creates >= existing_creates or not existing:
                    self._cookie_cache[key] = cookie
        elif kind == "clear_cookies":
            self._cookie_cache.clear()
            self._pending_clear_cookies = True

    def _cookie_key(self, name: str, domain: str, path: str) -> str:
        """Generate Redis hash field key for a cookie."""
        return f"{name}:{domain}:{path}"

    async def set_cookie(self, cookie: dict[str, Any], context: Any) -> None:
        """Set a cookie and publish if changed."""
        if not self._enabled:
            await context.add_cookies([cookie])
            return

        name = cookie.get("name", "")
        domain = cookie.get("domain", "")
        path = cookie.get("path", "/")
        key = (name, domain, path)
        hash_field = self._cookie_key(name, domain, path)

        # Check if changed
        existing = self._cookie_cache.get(key, {})
        if existing == cookie:
            await context.add_cookies([cookie])
            return

        # Set in Redis
        await self._redis.hset(COOKIES_KEY, hash_field, json.dumps(cookie))
        # Update cache
        self._cookie_cache[key] = cookie
        # Set in browser
        await context.add_cookies([cookie])
        # Publish update
        await self._redis.publish(
            UPDATE_CHANNEL, json.dumps({"kind": "cookie", "cookie": cookie})
        )

    async def get_cookies(
        self, context: Any, urls: list[str] | None = None
    ) -> list[dict]:
        """Get cookies, including ones from Redis cache."""
        if not self._enabled:
            return await context.cookies(urls)

        # Apply any pending remote clear (from another instance's delete_cookies)
        if self._pending_clear_cookies:
            await context.clear_cookies()
            self._pending_clear_cookies = False

        # Build cache lookup for fast access
        cache_lookup = {
            self._cookie_key(c["name"], c["domain"], c["path"]): c
            for c in self._cookie_cache.values()
        }

        # Get from browser; cache wins on conflict (it has the latest pubsub value)
        browser_cookies = await context.cookies(urls)
        merged: dict[str, dict] = {}
        for c in browser_cookies:
            hf = self._cookie_key(c["name"], c["domain"], c["path"])
            cached = cache_lookup.get(hf)
            if cached and cached != c:
                # Browser has stale value — update it and use cache version
                await context.add_cookies([cached])
                merged[hf] = cached
            else:
                merged[hf] = c

        # Add cached cookies not present in browser at all
        for hf, cookie in cache_lookup.items():
            if hf not in merged:
                await context.add_cookies([cookie])
                merged[hf] = cookie

        return list(merged.values())

    async def delete_cookies(self, context: Any) -> None:
        """Clear all cookies and publish."""
        if not self._enabled:
            await context.clear_cookies()
            return

        await context.clear_cookies()
        # Clear cache
        self._cookie_cache.clear()
        # Publish clear
        msg = json.dumps({"kind": "clear_cookies"})
        await self._redis.publish(UPDATE_CHANNEL, msg)
        # Clear in Redis (delete the whole hash)
        await self._redis.delete(COOKIES_KEY)
