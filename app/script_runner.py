"""Script execution mode - run YAML automation scripts and exit."""

from __future__ import annotations

import base64
import json
import os
import re
import sys
import time
from typing import Any, Awaitable, Callable

import yaml
from logger import get_logger

log = get_logger(__name__)


def load_script(path: str) -> dict[str, Any]:
    """Load a YAML script from file."""
    if not os.path.isfile(path):
        raise FileNotFoundError(f"Script not found: {path}")
    with open(path) as f:
        data = yaml.safe_load(f)

    if not data or not isinstance(data, dict):
        raise ValueError("Invalid script: expected a YAML mapping")

    if "steps" not in data or not data["steps"]:
        raise ValueError("Invalid script: no steps defined")

    return data


def _substitute_env(value: str) -> str:
    """Replace ${env.VAR} placeholders with environment variable values."""
    return re.sub(
        r"\$\{env\.([^}]+)\}",
        lambda m: os.environ.get(m.group(1), ""),
        value,
    )


def substitute_step_vars(step: dict[str, Any]) -> dict[str, Any]:
    """Replace variable placeholders in all string values of a step."""
    out: dict[str, Any] = {}
    for k, v in step.items():
        if isinstance(v, str):
            out[k] = _substitute_env(v)
        else:
            out[k] = v
    return out


def _extract_output(result: dict[str, Any]) -> Any:
    """Extract the output value from a step result.

    For binary data (screenshots), base64-encode with data URI prefix.
    For everything else, return the data dict as-is.
    """
    raw = result.get("_binary")
    if raw:
        encoded = base64.b64encode(raw).decode("ascii")
        return f"data:image/png;base64,{encoded}"

    return result.get("data")


async def run_script(
    script_data: dict[str, Any],
    dispatch_fn: Callable[[dict[str, Any]], Awaitable[dict]],
    stdout: Any = None,
) -> dict[str, Any]:
    """Execute script steps and return results dict.

    Results JSON is printed to stdout. Logs go to stderr.
    Steps with output_id have their results collected in outputs dict.
    """
    if stdout is None:
        stdout = sys.stdout
    name = script_data.get("name", "unnamed")
    on_error = script_data.get("on_error", "stop")
    steps = script_data.get("steps", [])

    step_results: list[dict[str, Any]] = []
    outputs: dict[str, Any] = {}
    all_success = True
    start_time = time.time()

    log.info(f"Running: {name} ({len(steps)} steps)")

    for i, raw_step in enumerate(steps):
        step = substitute_step_vars(raw_step)
        action = step.get("action", "")
        output_id = step.get("output_id")
        step_start = time.time()

        log.info(f"  [{i + 1}/{len(steps)}] {action}")

        try:
            result = await dispatch_fn(step)
        except Exception as e:
            result = {"success": False, "error": str(e)}

        # Collect named output
        if output_id and result.get("success"):
            outputs[output_id] = _extract_output(result)

        # Strip binary from serialized step_results
        result.pop("_binary", None)

        step_result = {
            "step": i + 1,
            "action": action,
            "duration": round(time.time() - step_start, 3),
            **result,
        }
        step_results.append(step_result)

        if not result.get("success", True):
            all_success = False
            err = result.get("error", "?")
            log.warning("  [%d/%d] FAILED: %s", i + 1, len(steps), err)
            if on_error == "stop":
                break
            continue

        log.info(f"  [{i + 1}/{len(steps)}] OK ({step_result['duration']}s)")

    total_duration = round(time.time() - start_time, 3)
    num_executed = len(step_results)

    output: dict[str, Any] = {
        "name": name,
        "success": all_success,
        "steps_executed": num_executed,
        "steps_total": len(steps),
        "duration": total_duration,
        "step_results": step_results,
    }
    if outputs:
        output["outputs"] = outputs

    log.info(
        f"Done: {num_executed}/{len(steps)} steps in {total_duration}s"
        f" - {'OK' if all_success else 'FAILED'}"
    )

    print(json.dumps(output, indent=2, default=str), file=stdout, flush=True)

    return output
