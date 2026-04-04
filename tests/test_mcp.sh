#!/usr/bin/env bash
# tests/test_mcp.sh — MCP Streamable HTTP server integration tests.
#
# Sourced by test.sh; registered as test_mcp in ALL_TESTS.

test_mcp() {(
    set -euo pipefail
    local PASS=0 FAIL=0

    _pass() { echo "  OK: $1"; PASS=$((PASS + 1)); }
    _fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

    echo "--- test_mcp ---"

    # Run all MCP tests via a single Python script
    local result
    result=$(python3 - "$BASE" "$TEST_PAGE" << 'PYEOF'
import json, sys, urllib.request

base_url = sys.argv[1]
test_page = sys.argv[2]
mcp_url = f"{base_url}/mcp/"
session_id = None

def mcp_request(id_num, method, params=None):
    global session_id
    body = {"jsonrpc": "2.0", "id": id_num, "method": method}
    if params:
        body["params"] = params
    data = json.dumps(body).encode()
    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json, text/event-stream",
    }
    if session_id:
        headers["Mcp-Session-Id"] = session_id
    req = urllib.request.Request(mcp_url, data=data, headers=headers)
    resp = urllib.request.urlopen(req, timeout=30)
    session_id = resp.headers.get("mcp-session-id", session_id)
    raw = resp.read().decode()
    for line in raw.splitlines():
        line = line.strip()
        if line.startswith("data: "):
            return json.loads(line[6:])
    return None

def mcp_notify(method):
    body = {"jsonrpc": "2.0", "method": method}
    data = json.dumps(body).encode()
    headers = {"Content-Type": "application/json"}
    if session_id:
        headers["Mcp-Session-Id"] = session_id
    req = urllib.request.Request(mcp_url, data=data, headers=headers)
    try:
        urllib.request.urlopen(req, timeout=5)
    except Exception:
        pass

def tool_call(id_num, name, args=None):
    params = {"name": name, "arguments": args or {}}
    return mcp_request(id_num, "tools/call", params)

def tool_text(resp):
    """Extract text content from tool call response."""
    if not resp:
        return ""
    content = resp.get("result", {}).get("content", [])
    for c in content:
        if c.get("type") == "text":
            return c["text"]
    return ""

results = []

# 1. Initialize
try:
    r = mcp_request(1, "initialize", {
        "protocolVersion": "2025-03-26",
        "capabilities": {},
        "clientInfo": {"name": "test", "version": "0.1"}
    })
    mcp_notify("notifications/initialized")
    ok = session_id is not None and r is not None
    results.append(("1. MCP initialize", ok, "" if ok else "no session"))
except Exception as e:
    results.append(("1. MCP initialize", False, str(e)))

# 2. List tools
try:
    r = mcp_request(2, "tools/list", {})
    tools = r.get("result", {}).get("tools", [])
    names = [t["name"] for t in tools]
    ok = len(tools) >= 15
    results.append((f"2. tools/list ({len(tools)} tools)", ok, ""))
    expected = ["goto","get_text","get_html","screenshot","system_click","eval_js","browser_action"]
    missing = [n for n in expected if n not in names]
    ok2 = len(missing) == 0
    results.append(("2b. expected tools present", ok2, f"missing: {missing}" if missing else ""))
except Exception as e:
    results.append(("2. tools/list", False, str(e)))

# 3. goto
try:
    r = tool_call(3, "goto", {"url": test_page, "wait_until": "networkidle"})
    txt = tool_text(r)
    ok = '"success": true' in txt or '"success":true' in txt
    results.append(("3. goto", ok, txt[:80] if not ok else ""))
except Exception as e:
    results.append(("3. goto", False, str(e)))

# 4. get_text
try:
    r = tool_call(4, "get_text")
    txt = tool_text(r)
    ok = "Submit" in txt
    results.append(("4. get_text", ok, txt[:80] if not ok else ""))
except Exception as e:
    results.append(("4. get_text", False, str(e)))

# 5. eval_js
try:
    r = tool_call(5, "eval_js", {"expression": "document.title"})
    txt = tool_text(r)
    ok = "Test Page" in txt
    results.append(("5. eval_js", ok, txt[:80] if not ok else ""))
except Exception as e:
    results.append(("5. eval_js", False, str(e)))

# 6. system_click
try:
    r = tool_call(6, "system_click", {"x": 500, "y": 300})
    txt = tool_text(r)
    ok = '"success": true' in txt or '"success":true' in txt
    results.append(("6. system_click", ok, txt[:80] if not ok else ""))
except Exception as e:
    results.append(("6. system_click", False, str(e)))

# 7. browser_action ping
try:
    r = tool_call(7, "browser_action", {"action": "ping"})
    txt = tool_text(r)
    ok = "pong" in txt
    results.append(("7. browser_action ping", ok, txt[:80] if not ok else ""))
except Exception as e:
    results.append(("7. browser_action ping", False, str(e)))

# 8. browser_action cookies
try:
    tool_call(80, "goto", {"url": test_page})
    r = tool_call(81, "browser_action", {"action": "set_cookie", "params": {"name": "mcp_test", "value": "mcp_val", "url": test_page}})
    txt = tool_text(r)
    ok1 = "mcp_test" in txt
    results.append(("8a. set_cookie", ok1, txt[:80] if not ok1 else ""))

    r = tool_call(82, "browser_action", {"action": "get_cookies"})
    txt = tool_text(r)
    ok2 = "mcp_test" in txt
    results.append(("8b. get_cookies", ok2, txt[:80] if not ok2 else ""))
except Exception as e:
    results.append(("8. cookies", False, str(e)))

# 9. screenshot
try:
    r = tool_call(9, "screenshot", {"whLargest": 256})
    content = r.get("result", {}).get("content", [])
    has_img = any(c.get("type") == "image" for c in content)
    results.append(("9. screenshot image", has_img, "no image content" if not has_img else ""))
except Exception as e:
    results.append(("9. screenshot", False, str(e)))

# 10. run_script
try:
    r = tool_call(10, "run_script", {
        "steps": [
            {"action": "goto", "url": test_page, "wait_until": "load"},
            {"action": "eval", "expression": "document.title", "output_id": "title"}
        ]
    })
    txt = tool_text(r)
    ok = "Test Page" in txt and '"success": true' in txt or '"success":true' in txt
    results.append(("10. run_script", ok, txt[:120] if not ok else ""))
except Exception as e:
    results.append(("10. run_script", False, str(e)))

# Output results as JSON for shell to parse
print(json.dumps(results))
PYEOF
    ) || true

    # Parse Python results
    echo "$result" | python3 -c "
import sys, json
results = json.loads(sys.stdin.read())
for name, ok, err in results:
    if ok:
        print(f'  OK: {name}')
    else:
        msg = f': {err}' if err else ''
        print(f'  FAIL: {name}{msg}')
" 2>/dev/null || true

    local pass_count fail_count
    pass_count=$(echo "$result" | python3 -c "import sys,json; r=json.loads(sys.stdin.read()); print(sum(1 for _,ok,_ in r if ok))" 2>/dev/null || echo 0)
    fail_count=$(echo "$result" | python3 -c "import sys,json; r=json.loads(sys.stdin.read()); print(sum(1 for _,ok,_ in r if not ok))" 2>/dev/null || echo 0)

    PASS=$pass_count
    FAIL=$fail_count

    echo ""
    echo "  MCP results: $PASS passed, $FAIL failed"
    [ "$FAIL" -gt 0 ] && return 1
    return 0
)}

ALL_TESTS+=(test_mcp)
