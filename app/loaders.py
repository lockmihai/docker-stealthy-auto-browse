"""URL-triggered page loaders (Greasemonkey-style)."""

from __future__ import annotations

import os
import re
from dataclasses import dataclass, field
from typing import Any
from urllib.parse import urlparse

import yaml


@dataclass
class Loader:
    """A URL-matching page loader."""

    name: str
    match_domain: str | None = None
    match_path_prefix: str | None = None
    match_regex: str | None = None
    steps: list[dict[str, Any]] = field(default_factory=list)


def load_loaders(loaders_dir: str) -> list[Loader]:
    """Load all YAML loader files from a directory."""
    loaders: list[Loader] = []
    if not os.path.isdir(loaders_dir):
        return loaders

    for fname in sorted(os.listdir(loaders_dir)):
        if not fname.endswith((".yaml", ".yml")):
            continue

        path = os.path.join(loaders_dir, fname)
        try:
            with open(path) as f:
                data = yaml.safe_load(f)
        except Exception as e:
            print(f"[loaders] Failed to load {fname}: {e}")
            continue

        if not data or not isinstance(data, dict):
            continue

        match = data.get("match", {})
        if not match:
            print(f"[loaders] Skipping {fname}: no match section")
            continue

        loader = Loader(
            name=data.get("name", fname),
            match_domain=match.get("domain"),
            match_path_prefix=match.get("path_prefix"),
            match_regex=match.get("regex"),
            steps=data.get("steps", []),
        )
        loaders.append(loader)
        print(f"[loaders] Loaded: {loader.name} ({fname})")

    return loaders


def _strip_www(host: str) -> str:
    if host.startswith("www."):
        return host[4:]
    return host


def find_loader(loaders: list[Loader], url: str) -> Loader | None:
    """Find first loader matching the given URL."""
    parsed = urlparse(url)
    host = _strip_www(parsed.hostname or "")
    path = parsed.path or "/"

    for loader in loaders:
        if loader.match_domain:
            if _strip_www(loader.match_domain) != host:
                continue

        if loader.match_path_prefix:
            if not path.startswith(loader.match_path_prefix):
                continue

        if loader.match_regex:
            if not re.search(loader.match_regex, url):
                continue

        return loader

    return None


def substitute_url(step: dict[str, Any], url: str) -> dict[str, Any]:
    """Replace ${url} placeholders in all string values of a step."""
    out: dict[str, Any] = {}
    for k, v in step.items():
        if isinstance(v, str):
            out[k] = v.replace("${url}", url)
        else:
            out[k] = v
    return out
