"""Centralized JSON logger for all app modules.

Usage:
    from logger import get_logger
    log = get_logger(__name__)
    log.info("something happened")
    log.warning("watch out", extra={"key": "value"})

Output (one JSON object per line):
    {"ts":"21:05:33","level":"INFO","src":"main:42","msg":"something happened"}
    {"ts":"21:05:34","level":"WARNING","src":"main:55","msg":"watch out","key":"value"}
"""

from __future__ import annotations

import json
import logging
import sys
from datetime import datetime
from typing import Any


class _JSONFormatter(logging.Formatter):
    """Format log records as single-line JSON."""

    def format(self, record: logging.LogRecord) -> str:
        entry: dict[str, object] = {
            "ts": datetime.fromtimestamp(record.created).strftime("%H:%M:%S"),
            "level": record.levelname,
            "src": f"{record.module}:{record.funcName}:{record.lineno}",
            "msg": record.getMessage(),
        }
        # Merge any extra keys passed via extra={...}
        for k, v in record.__dict__.items():
            if k not in _RESERVED and k not in entry:
                entry[k] = v
        return json.dumps(entry, default=str)


# Standard LogRecord attributes to exclude from extras
_RESERVED = frozenset(
    {
        "name",
        "msg",
        "args",
        "created",
        "relativeCreated",
        "exc_info",
        "exc_text",
        "stack_info",
        "lineno",
        "funcName",
        "filename",
        "module",
        "levelname",
        "levelno",
        "pathname",
        "process",
        "processName",
        "thread",
        "threadName",
        "msecs",
        "message",
        "taskName",
    }
)

_configured = False


def configure_output(stream: Any = None) -> None:
    """Reconfigure logging output stream (e.g. stderr for script mode)."""
    if stream is None:
        stream = sys.stdout
    handler = logging.StreamHandler(stream)
    handler.setFormatter(_JSONFormatter())
    logging.root.handlers = [handler]
    logging.root.setLevel(logging.INFO)


def get_logger(name: str) -> logging.Logger:
    """Get a logger that outputs JSON to stdout."""
    global _configured
    if not _configured:
        configure_output(sys.stdout)
        _configured = True
    return logging.getLogger(name)
