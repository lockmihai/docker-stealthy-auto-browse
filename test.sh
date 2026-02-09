#!/bin/bash
set -euo pipefail

IMAGE_NAME="psyb0t/stealthy-auto-browse"
TEST_TAG="latest-test"
CONTAINER_NAME="stealthy-auto-browse-test"
INTERNAL_PORT="8080"
BASE=""
WORKDIR="$(cd "$(dirname "$0")" && pwd)"
TESTDATA_DIR="$WORKDIR/.testdata"

# Track extra containers for cleanup
EXTRA_CONTAINERS=()

# Test fixture HTML file (has form inputs, click handlers, screen info)
TEST_FIXTURE="$WORKDIR/.fixtures/test.html"
TEST_FIXTURE_PATH="/tmp/test_fixture.html"

# --- Helpers ---

json_get() {
    python3 -c "import sys,json; print(json.load(sys.stdin)$1)"
}

png_dimensions() {
    python3 -c "
from struct import unpack
with open('$1','rb') as f:
    f.read(16)
    w,h = unpack('>II', f.read(8))
    print(f'{w}x{h}')
"
}

post_to() {
    local base="$1"
    local data="$2"
    curl -sf -X POST "$base" -H "Content-Type: application/json" -d "$data"
}

post() {
    post_to "$BASE" "$1"
}

assert_success() {
    local resp="$1"
    local name="$2"
    if ! echo "$resp" | grep -q '"success": true'; then
        echo "FAIL: $name: $resp"
        return 1
    fi
    echo "OK: $name"
}

assert_http_ok() {
    local url="$1"
    local name="$2"
    local code
    code=$(curl -sf -o /dev/null -w "%{http_code}" "$url")
    if [ "$code" != "200" ]; then
        echo "FAIL: $name: HTTP $code"
        return 1
    fi
    echo "OK: $name"
}

assert_eq() {
    local actual="$1"
    local expected="$2"
    local name="$3"
    if [ "$actual" != "$expected" ]; then
        echo "FAIL: $name: expected $expected, got $actual"
        return 1
    fi
}

start_extra_container() {
    local name="$1"
    shift
    docker rm -f "$name" 2>/dev/null || true
    docker run -d --name "$name" "$@" "$IMAGE_NAME:$TEST_TAG" >/dev/null
    EXTRA_CONTAINERS+=("$name")
    docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$name"
}

wait_for_api() {
    local base_url="$1"
    local max_wait="${2:-30}"
    for i in $(seq 1 "$max_wait"); do
        if curl -sf "$base_url/health" >/dev/null 2>&1; then
            return 0
        fi
        if [ "$i" -eq "$max_wait" ]; then
            return 1
        fi
        sleep 2
    done
}

stop_extra_container() {
    local name="$1"
    docker rm -f "$name" 2>/dev/null || true
}

inject_test_fixture() {
    local container="$1"
    docker cp "$TEST_FIXTURE" "${container}:${TEST_FIXTURE_PATH}"
}

# --- Per-test setup/teardown (main container only) ---

test_setup() {
    post '{"action": "goto", "url": "file:///tmp/test_fixture.html"}' >/dev/null
    sleep 1
}

test_teardown() {
    # Reset scroll position
    post '{"action": "eval", "expression": "window.scrollTo(0,0)"}' >/dev/null 2>&1 || true
    # Exit fullscreen if active
    post '{"action": "exit_fullscreen"}' >/dev/null 2>&1 || true
}

# --- Test functions ---

test_ping() {
    local resp msg
    resp=$(post '{"action": "ping"}')
    assert_success "$resp" "ping" || return 1
    msg=$(echo "$resp" | json_get "['data']['message']")
    assert_eq "$msg" "pong" "ping: message"
}

test_goto() {
    local resp title
    resp=$(post '{"action": "goto", "url": "file:///tmp/test_fixture.html"}')
    assert_success "$resp" "goto" || return 1
    title=$(echo "$resp" | json_get "['data']['title']")
    assert_eq "$title" "Test Page" "goto: page title"
}

test_get_text() {
    local resp text
    resp=$(post '{"action": "get_text"}')
    assert_success "$resp" "get_text" || return 1
    text=$(echo "$resp" | json_get "['data']['text']")
    echo "$text" | grep -q "Submit" || { echo "FAIL: get_text: missing 'Submit' in text"; return 1; }
    echo "OK: get_text (contains 'Submit')"
}

test_get_html() {
    local resp html
    resp=$(post '{"action": "get_html"}')
    assert_success "$resp" "get_html" || return 1
    html=$(echo "$resp" | json_get "['data']['html']")
    echo "$html" | grep -q "test-form" || { echo "FAIL: get_html: missing 'test-form' in html"; return 1; }
    echo "$html" | grep -q "name-input" || { echo "FAIL: get_html: missing 'name-input' in html"; return 1; }
    echo "OK: get_html (contains form elements)"
}

test_get_interactive_elements() {
    local resp elements
    resp=$(post '{"action": "get_interactive_elements"}')
    assert_success "$resp" "get_interactive_elements" || return 1
    # Should find at least the 2 inputs + 1 button = 3 elements
    elements=$(echo "$resp" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['data']['elements']))")
    if [ "$elements" -lt 3 ]; then
        echo "FAIL: get_interactive_elements: expected >= 3, got $elements"
        return 1
    fi
    echo "OK: get_interactive_elements ($elements elements found)"
}

test_get_resolution() {
    local resp w h
    resp=$(post '{"action": "get_resolution"}')
    assert_success "$resp" "get_resolution" || return 1

    # Default container runs at 1920x1080
    w=$(echo "$resp" | json_get "['data']['width']")
    h=$(echo "$resp" | json_get "['data']['height']")
    assert_eq "$w" "1920" "get_resolution: width" || return 1
    assert_eq "$h" "1080" "get_resolution: height" || return 1
    echo "OK: get_resolution (1920x1080 verified)"
}

test_calibrate() {
    local resp offset_x offset_y
    resp=$(post '{"action": "calibrate"}')
    assert_success "$resp" "calibrate" || return 1
    offset_x=$(echo "$resp" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['window_offset']['x'])")
    offset_y=$(echo "$resp" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['window_offset']['y'])")
    # x should be 0 (no side chrome), y should be realistic chrome height (40-100px)
    assert_eq "$offset_x" "0" "calibrate: offset x" || return 1
    if [ "$offset_y" -lt 40 ] || [ "$offset_y" -gt 100 ]; then
        echo "FAIL: calibrate: offset y=$offset_y outside expected range 40-100"
        return 1
    fi
    echo "OK: calibrate (offset: $offset_x,$offset_y)"
}

test_eval() {
    local resp val
    resp=$(post '{"action": "eval", "expression": "document.title"}')
    assert_success "$resp" "eval" || return 1
    val=$(echo "$resp" | json_get "['data']['result']")
    assert_eq "$val" "Test Page" "eval: document.title"
}

test_screenshot_browser() {
    local tmpdir="$TESTDATA_DIR/screenshots"
    mkdir -p "$tmpdir"
    curl -sf "$BASE/screenshot/browser" -o "$tmpdir/browser.png"
    # Verify it's a valid PNG with width=1920 (height varies due to browser chrome)
    local dims w
    dims=$(png_dimensions "$tmpdir/browser.png")
    w="${dims%%x*}"
    assert_eq "$w" "1920" "screenshot/browser: width"
}

test_screenshot_desktop() {
    local tmpdir="$TESTDATA_DIR/screenshots"
    mkdir -p "$tmpdir"
    curl -sf "$BASE/screenshot/desktop" -o "$tmpdir/desktop.png"
    # Verify it's a valid PNG with 1920x1080 dimensions (default resolution)
    local dims
    dims=$(png_dimensions "$tmpdir/desktop.png")
    assert_eq "$dims" "1920x1080" "screenshot/desktop: dimensions"
}

test_screenshot_resize() {
    local tmpdir="$TESTDATA_DIR/screenshots"
    mkdir -p "$tmpdir"

    # Get original browser screenshot dimensions for ratio calculations
    curl -sf "$BASE/screenshot/browser" -o "$tmpdir/orig.png"
    local orig_dims orig_w orig_h
    orig_dims=$(png_dimensions "$tmpdir/orig.png")
    orig_w="${orig_dims%%x*}"
    orig_h="${orig_dims##*x}"

    # Cases: "label|query_params|expected_width|expected_height"
    local cases=(
        "width_only|width=800|800|$(( orig_h * 800 / orig_w ))"
        "height_only|height=300|$(( orig_w * 300 / orig_h ))|300"
        "width_and_height|width=400&height=400|400|400"
        "whLargest|whLargest=512|512|$(( orig_h * 512 / orig_w ))"
    )

    local entry label params exp_w exp_h
    for entry in "${cases[@]}"; do
        IFS='|' read -r label params exp_w exp_h <<< "$entry"
        curl -sf "$BASE/screenshot/browser?${params}" -o "$tmpdir/resize_${label}.png"
        local dims w h
        dims=$(png_dimensions "$tmpdir/resize_${label}.png")
        w="${dims%%x*}"
        h="${dims##*x}"
        assert_eq "$w" "$exp_w" "screenshot_resize[$label]: width" || return 1
        assert_eq "$h" "$exp_h" "screenshot_resize[$label]: height" || return 1
    done

    # Also verify desktop resize works
    curl -sf "$BASE/screenshot/desktop?whLargest=256" -o "$tmpdir/resize_desktop.png"
    local desk_dims desk_w desk_h
    desk_dims=$(png_dimensions "$tmpdir/resize_desktop.png")
    desk_w="${desk_dims%%x*}"
    desk_h="${desk_dims##*x}"
    # Default is 1920x1080, width is largest so should be 256
    assert_eq "$desk_w" "256" "screenshot_resize[desktop_whLargest]: width" || return 1

    echo "OK: screenshot_resize (${#cases[@]} browser cases + desktop)"
}

test_state() {
    local resp status
    resp=$(curl -sf "$BASE/state")
    status=$(echo "$resp" | json_get "['status']")
    assert_eq "$status" "ready" "state: status" || return 1
    # Verify response has expected fields
    echo "$resp" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert 'url' in d, 'missing url'
assert 'title' in d, 'missing title'
assert 'window_offset' in d, 'missing window_offset'
" || { echo "FAIL: state: missing expected fields"; return 1; }
    echo "OK: state (status=ready)"
}

test_health() {
    local resp
    resp=$(curl -sf "$BASE/health")
    assert_eq "$resp" "ok" "health: response body"
}

test_mouse_move() {
    # Move mouse to known position and verify via pyautogui
    post '{"action": "mouse_move", "x": 250, "y": 250, "duration": 0.1}' >/dev/null
    local resp pos_x pos_y
    resp=$(post '{"action": "eval", "expression": "null"}')
    # Verify action succeeded (mouse_move has no visible DOM effect, check position via API)
    resp=$(post '{"action": "mouse_move", "x": 500, "y": 400, "duration": 0.1}')
    assert_success "$resp" "mouse_move"
}

test_mouse_click() {
    # Click on the submit button via mouse_click (pyautogui) and verify DOM event fired
    post '{"action": "calibrate"}' >/dev/null
    # Get submit button center coordinates
    local resp rect_raw btn_x btn_y val
    resp=$(post '{"action": "eval", "expression": "JSON.stringify(document.getElementById(\"submit-btn\").getBoundingClientRect())"}')
    rect_raw=$(echo "$resp" | json_get "['data']['result']")
    btn_x=$(echo "$rect_raw" | python3 -c "import sys,json; r=json.loads(sys.stdin.read()); print(int(r['x']+r['width']/2))")
    btn_y=$(echo "$rect_raw" | python3 -c "import sys,json; r=json.loads(sys.stdin.read()); print(int(r['y']+r['height']/2))")
    post "{\"action\": \"mouse_click\", \"x\": $btn_x, \"y\": $btn_y}" >/dev/null
    sleep 0.5
    resp=$(post '{"action": "eval", "expression": "var e=document.getElementById(\"btn-clicked\"); e ? e.textContent : \"\""}')
    val=$(echo "$resp" | json_get "['data']['result']")
    assert_eq "$val" "clicked" "mouse_click: button clicked via coordinates"
}

test_system_click() {
    # Click on an input field via system_click, type into it to verify focus
    post '{"action": "calibrate"}' >/dev/null
    # Get name-input center coordinates
    local resp rect_raw inp_x inp_y val
    resp=$(post '{"action": "eval", "expression": "JSON.stringify(document.getElementById(\"name-input\").getBoundingClientRect())"}')
    rect_raw=$(echo "$resp" | json_get "['data']['result']")
    inp_x=$(echo "$rect_raw" | python3 -c "import sys,json; r=json.loads(sys.stdin.read()); print(int(r['x']+r['width']/2))")
    inp_y=$(echo "$rect_raw" | python3 -c "import sys,json; r=json.loads(sys.stdin.read()); print(int(r['y']+r['height']/2))")
    post "{\"action\": \"system_click\", \"x\": $inp_x, \"y\": $inp_y}" >/dev/null
    sleep 0.5
    post '{"action": "system_type", "text": "sc", "interval": 0.02}' >/dev/null
    sleep 0.5
    resp=$(post '{"action": "eval", "expression": "document.getElementById(\"name-input\").value"}')
    val=$(echo "$resp" | json_get "['data']['result']")
    assert_eq "$val" "sc" "system_click: input focused and typed into"
}

test_scroll() {
    # Get initial scroll position
    local resp before after
    resp=$(post '{"action": "eval", "expression": "window.scrollY"}')
    before=$(echo "$resp" | json_get "['data']['result']")
    # Scroll down
    post '{"action": "scroll", "amount": -5}' >/dev/null
    sleep 0.5
    resp=$(post '{"action": "eval", "expression": "window.scrollY"}')
    after=$(echo "$resp" | json_get "['data']['result']")
    if [ "$after" -le "$before" ]; then
        echo "FAIL: scroll: scrollY didn't increase (before=$before, after=$after)"
        return 1
    fi
    echo "OK: scroll (scrollY: $before -> $after)"
}

test_system_type() {
    # Click on sys-input to focus it, then system_type into it
    post '{"action": "click", "selector": "#sys-input"}' >/dev/null
    sleep 0.3
    post '{"action": "system_type", "text": "hello", "interval": 0.02}' >/dev/null
    sleep 0.5
    local resp val
    resp=$(post '{"action": "eval", "expression": "document.getElementById(\"sys-input\").value"}')
    val=$(echo "$resp" | json_get "['data']['result']")
    assert_eq "$val" "hello" "system_type: input value"
}

test_send_key() {
    # Send a key and check the keydown listener captured it
    post '{"action": "send_key", "key": "a"}' >/dev/null
    sleep 0.3
    local resp val
    resp=$(post '{"action": "eval", "expression": "document.getElementById(\"last-key\").textContent"}')
    val=$(echo "$resp" | json_get "['data']['result']")
    assert_eq "$val" "a" "send_key: keydown listener captured 'a'"
}

test_enter_fullscreen() {
    post '{"action": "enter_fullscreen"}' >/dev/null
    sleep 1
    local resp val
    resp=$(post '{"action": "eval", "expression": "!!document.fullscreenElement"}')
    val=$(echo "$resp" | json_get "['data']['result']")
    assert_eq "$val" "True" "enter_fullscreen: fullscreenElement set"
}

test_exit_fullscreen() {
    # Enter fullscreen first so this test is self-contained
    post '{"action": "enter_fullscreen"}' >/dev/null
    sleep 1
    post '{"action": "exit_fullscreen"}' >/dev/null
    sleep 1
    local resp val
    resp=$(post '{"action": "eval", "expression": "!!document.fullscreenElement"}')
    val=$(echo "$resp" | json_get "['data']['result']")
    assert_eq "$val" "False" "exit_fullscreen: fullscreenElement cleared"
}

test_fill() {
    post '{"action": "fill", "selector": "#name-input", "value": "hello world"}' >/dev/null
    local resp val
    resp=$(post '{"action": "eval", "expression": "document.getElementById(\"name-input\").value"}')
    val=$(echo "$resp" | json_get "['data']['result']")
    assert_eq "$val" "hello world" "fill: input value"
}

test_type_action() {
    post '{"action": "click", "selector": "#email-input"}' >/dev/null
    post '{"action": "type", "selector": "#email-input", "text": "typed", "delay": 0.02}' >/dev/null
    local resp val
    resp=$(post '{"action": "eval", "expression": "document.getElementById(\"email-input\").value"}')
    val=$(echo "$resp" | json_get "['data']['result']")
    assert_eq "$val" "typed" "type: input value"
}

test_click() {
    post '{"action": "click", "selector": "#submit-btn"}' >/dev/null
    sleep 0.5
    local resp val
    resp=$(post '{"action": "eval", "expression": "document.getElementById(\"btn-clicked\") ? document.getElementById(\"btn-clicked\").textContent : \"\""}')
    val=$(echo "$resp" | json_get "['data']['result']")
    assert_eq "$val" "clicked" "click: button creates element"
}

# --- Env var tests (spawn separate containers) ---

# --- Table-driven resolution tests ---
# Each case: "label|WxH|use_viewport|check_browser|check_desktop"
# JS screen dims and API dims are always checked.
RESOLUTION_CASES=(
    "1280x720|1280x720|false|false|true"
    "800x600-viewport|800x600|true|true|true"
    "375x812-phone|375x812|true|true|false"
    "800x800-square|800x800|false|false|true"
)

_run_resolution_case() {
    local label="$1"
    local resolution="$2"
    local use_viewport="$3"
    local check_browser="$4"
    local check_desktop="$5"

    local w="${resolution%%x*}"
    local h="${resolution##*x}"
    local name="${CONTAINER_NAME}-res-${label}"
    local tmpdir="$TESTDATA_DIR/res-${label}"
    mkdir -p "$tmpdir"

    local docker_args=(-e "XVFB_RESOLUTION=${resolution}")
    if [ "$use_viewport" = "true" ]; then
        docker_args+=(-e USE_VIEWPORT=true)
    fi

    local ip base
    ip=$(start_extra_container "$name" "${docker_args[@]}")
    base="http://${ip}:${INTERNAL_PORT}"

    if ! wait_for_api "$base" 90; then
        echo "FAIL: resolution[${label}]: API not ready"
        docker logs "$name" 2>&1 | tail -20
        stop_extra_container "$name"
        return 1
    fi

    inject_test_fixture "$name"
    post_to "$base" '{"action": "goto", "url": "file:///tmp/test_fixture.html"}' >/dev/null
    sleep 1

    # JS screen dimensions
    local resp js_w js_h
    resp=$(post_to "$base" '{"action": "eval", "expression": "screen.width"}')
    js_w=$(echo "$resp" | json_get "['data']['result']")
    resp=$(post_to "$base" '{"action": "eval", "expression": "screen.height"}')
    js_h=$(echo "$resp" | json_get "['data']['result']")
    assert_eq "$js_w" "$w" "resolution[${label}]: JS screen.width" || { stop_extra_container "$name"; return 1; }
    assert_eq "$js_h" "$h" "resolution[${label}]: JS screen.height" || { stop_extra_container "$name"; return 1; }

    # Desktop screenshot
    if [ "$check_desktop" = "true" ]; then
        curl -sf "$base/screenshot/desktop" -o "$tmpdir/desktop.png"
        local dims
        dims=$(png_dimensions "$tmpdir/desktop.png")
        assert_eq "$dims" "${resolution}" "resolution[${label}]: desktop screenshot" || { stop_extra_container "$name"; return 1; }
    fi

    # Browser screenshot (only with USE_VIEWPORT)
    if [ "$check_browser" = "true" ]; then
        curl -sf "$base/screenshot/browser" -o "$tmpdir/browser.png"
        local browser_dims
        browser_dims=$(png_dimensions "$tmpdir/browser.png")
        assert_eq "$browser_dims" "${resolution}" "resolution[${label}]: browser screenshot" || { stop_extra_container "$name"; return 1; }
    fi

    # API
    resp=$(post_to "$base" '{"action": "get_resolution"}')
    local api_w api_h
    api_w=$(echo "$resp" | json_get "['data']['width']")
    api_h=$(echo "$resp" | json_get "['data']['height']")
    assert_eq "$api_w" "$w" "resolution[${label}]: API width" || { stop_extra_container "$name"; return 1; }
    assert_eq "$api_h" "$h" "resolution[${label}]: API height" || { stop_extra_container "$name"; return 1; }

    stop_extra_container "$name"
    echo "  - ${label}: OK (JS ${resolution}, desktop ${resolution}, API ${resolution})"
}

test_resolution_matrix() {
    local entry label res viewport check_browser
    for entry in "${RESOLUTION_CASES[@]}"; do
        IFS='|' read -r label res viewport check_browser check_desktop <<< "$entry"
        _run_resolution_case "$label" "$res" "$viewport" "$check_browser" "$check_desktop" || return 1
    done
    echo "OK: resolution_matrix (${#RESOLUTION_CASES[@]} cases passed)"
}

test_persistent_profile_resolution() {
    # Test that changing XVFB_RESOLUTION with a persistent profile works.
    # 1. Start container at 800x800, let it generate a fingerprint config
    # 2. Stop it, start a new container at 1920x1080 with the same profile volume
    # 3. Verify the new container reports 1920x1080 (not the old 800x800)
    local name1="${CONTAINER_NAME}-persist-1"
    local name2="${CONTAINER_NAME}-persist-2"
    local profile_dir="$TESTDATA_DIR/persist-userdata"
    local tmpdir="$TESTDATA_DIR/persist-screenshots"
    mkdir -p "$profile_dir" "$tmpdir"

    # --- Phase 1: generate profile at 800x800 ---
    local ip base
    ip=$(start_extra_container "$name1" \
        -e "XVFB_RESOLUTION=800x800" \
        -v "$profile_dir:/userdata")
    base="http://${ip}:${INTERNAL_PORT}"

    if ! wait_for_api "$base" 90; then
        echo "FAIL: persistent_profile_resolution: phase 1 API not ready"
        docker logs "$name1" 2>&1 | tail -20
        stop_extra_container "$name1"
        return 1
    fi

    # Verify profile was created
    if [ ! -f "$profile_dir/stealthy-auto-browse-props.json" ]; then
        echo "FAIL: persistent_profile_resolution: fingerprint config not created"
        stop_extra_container "$name1"
        return 1
    fi

    # Verify 800x800 via JS
    inject_test_fixture "$name1"
    post_to "$base" '{"action": "goto", "url": "file:///tmp/test_fixture.html"}' >/dev/null
    sleep 1
    local resp js_w js_h
    resp=$(post_to "$base" '{"action": "eval", "expression": "screen.width"}')
    js_w=$(echo "$resp" | json_get "['data']['result']")
    resp=$(post_to "$base" '{"action": "eval", "expression": "screen.height"}')
    js_h=$(echo "$resp" | json_get "['data']['result']")
    assert_eq "$js_w" "800" "persistent_profile_resolution: phase 1 JS screen.width" || { stop_extra_container "$name1"; return 1; }
    assert_eq "$js_h" "800" "persistent_profile_resolution: phase 1 JS screen.height" || { stop_extra_container "$name1"; return 1; }

    # Desktop screenshot should be 800x800
    curl -sf "$base/screenshot/desktop" -o "$tmpdir/desktop_800x800.png"
    local dims
    dims=$(png_dimensions "$tmpdir/desktop_800x800.png")
    assert_eq "$dims" "800x800" "persistent_profile_resolution: phase 1 desktop screenshot" || { stop_extra_container "$name1"; return 1; }

    stop_extra_container "$name1"

    # --- Phase 2: reuse profile at 1920x1080 ---
    ip=$(start_extra_container "$name2" \
        -v "$profile_dir:/userdata")
    base="http://${ip}:${INTERNAL_PORT}"

    if ! wait_for_api "$base" 90; then
        echo "FAIL: persistent_profile_resolution: phase 2 API not ready"
        docker logs "$name2" 2>&1 | tail -20
        stop_extra_container "$name2"
        return 1
    fi

    inject_test_fixture "$name2"
    post_to "$base" '{"action": "goto", "url": "file:///tmp/test_fixture.html"}' >/dev/null
    sleep 1

    # JS should report 1920x1080 (updated from persisted config)
    resp=$(post_to "$base" '{"action": "eval", "expression": "screen.width"}')
    js_w=$(echo "$resp" | json_get "['data']['result']")
    resp=$(post_to "$base" '{"action": "eval", "expression": "screen.height"}')
    js_h=$(echo "$resp" | json_get "['data']['result']")
    assert_eq "$js_w" "1920" "persistent_profile_resolution: phase 2 JS screen.width" || { stop_extra_container "$name2"; return 1; }
    assert_eq "$js_h" "1080" "persistent_profile_resolution: phase 2 JS screen.height" || { stop_extra_container "$name2"; return 1; }

    # Desktop screenshot should be 1920x1080
    curl -sf "$base/screenshot/desktop" -o "$tmpdir/desktop_1920x1080.png"
    dims=$(png_dimensions "$tmpdir/desktop_1920x1080.png")
    assert_eq "$dims" "1920x1080" "persistent_profile_resolution: phase 2 desktop screenshot" || { stop_extra_container "$name2"; return 1; }

    # API should report 1920x1080
    resp=$(post_to "$base" '{"action": "get_resolution"}')
    local api_w api_h
    api_w=$(echo "$resp" | json_get "['data']['width']")
    api_h=$(echo "$resp" | json_get "['data']['height']")
    assert_eq "$api_w" "1920" "persistent_profile_resolution: phase 2 API width" || { stop_extra_container "$name2"; return 1; }
    assert_eq "$api_h" "1080" "persistent_profile_resolution: phase 2 API height" || { stop_extra_container "$name2"; return 1; }

    stop_extra_container "$name2"
    echo "OK: persistent_profile_resolution (800x800 -> 1920x1080 with same profile)"
}

# --- All test names ---

ALL_TESTS=(
    test_health
    test_ping
    test_state
    test_goto
    test_get_text
    test_get_html
    test_get_interactive_elements
    test_get_resolution
    test_calibrate
    test_eval
    test_screenshot_browser
    test_screenshot_desktop
    test_screenshot_resize
    test_mouse_move
    test_mouse_click
    test_system_click
    test_scroll
    test_system_type
    test_send_key
    test_enter_fullscreen
    test_exit_fullscreen
    test_fill
    test_type_action
    test_click
    test_resolution_matrix
    test_persistent_profile_resolution
)

# --- Usage ---

usage() {
    echo "Usage: $0 [test_name ...]"
    echo ""
    echo "Run with no args to run all tests."
    echo "Run with one or more test names to run specific tests."
    echo ""
    echo "Available tests:"
    for t in "${ALL_TESTS[@]}"; do
        echo "  $t"
    done
}

# --- Infrastructure setup ---

setup() {
    # Prepare testdata dir
    sudo rm -rf "$TESTDATA_DIR"
    mkdir -p "$TESTDATA_DIR"

    # Build test image
    echo "Building test image..."
    docker build -t "$IMAGE_NAME:$TEST_TAG" .

    # Remove any existing test container
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

    # Run test container
    echo "Starting test container..."
    docker run -d --name "$CONTAINER_NAME" "$IMAGE_NAME:$TEST_TAG"

    # Get the container IP
    local container_ip
    container_ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CONTAINER_NAME")
    if [ -z "$container_ip" ]; then
        echo "FAIL: Could not get container IP"
        exit 1
    fi

    BASE="http://${container_ip}:${INTERNAL_PORT}"
    echo "Container running at $BASE"

    # Wait for API
    echo "Waiting for API..."
    if ! wait_for_api "$BASE" 45; then
        echo "FAIL: API did not become ready in time"
        docker logs "$CONTAINER_NAME"
        exit 1
    fi
    echo "API ready"

    # Copy test fixture once (all main-container tests reuse it)
    inject_test_fixture "$CONTAINER_NAME"
}

cleanup() {
    echo "Cleaning up..."
    for c in "${EXTRA_CONTAINERS[@]}"; do
        docker rm -f "$c" 2>/dev/null || true
    done
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
    docker rmi "$IMAGE_NAME:$TEST_TAG" 2>/dev/null || true
    sudo rm -rf "$TESTDATA_DIR"
}
trap cleanup EXIT

# --- Main ---

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    usage
    exit 0
fi

TESTS_TO_RUN=("${@}")
if [ ${#TESTS_TO_RUN[@]} -eq 0 ]; then
    TESTS_TO_RUN=("${ALL_TESTS[@]}")
fi

# Validate test names
for t in "${TESTS_TO_RUN[@]}"; do
    if ! declare -f "$t" >/dev/null 2>&1; then
        echo "Unknown test: $t"
        echo ""
        usage
        exit 1
    fi
done

setup

echo ""
echo "=== Running ${#TESTS_TO_RUN[@]} test(s) ==="
echo ""

FAILED=0
PASSED=0

for t in "${TESTS_TO_RUN[@]}"; do
    test_setup
    if $t; then
        PASSED=$((PASSED + 1))
    else
        FAILED=$((FAILED + 1))
    fi
    test_teardown
done

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
