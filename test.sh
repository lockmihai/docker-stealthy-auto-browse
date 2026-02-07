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

# Test HTML that reports screen dimensions via JS
RESOLUTION_TEST_HTML='<!DOCTYPE html><html><body><div id="info"></div><script>document.getElementById("info").textContent=JSON.stringify({sw:screen.width,sh:screen.height,iw:window.innerWidth,ih:window.innerHeight});</script></body></html>'

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

inject_test_html() {
    local container="$1"
    docker exec "$container" sh -c "echo '$RESOLUTION_TEST_HTML' > /tmp/resolution_test.html"
}

# --- Test functions ---

test_ping() {
    assert_success "$(post '{"action": "ping"}')" "ping"
}

test_goto() {
    assert_success "$(post '{"action": "goto", "url": "https://www.google.com"}')" "goto"
    sleep 1
}

test_get_text() {
    assert_success "$(post '{"action": "get_text"}')" "get_text"
}

test_get_html() {
    assert_success "$(post '{"action": "get_html"}')" "get_html"
}

test_get_interactive_elements() {
    assert_success "$(post '{"action": "get_interactive_elements"}')" "get_interactive_elements"
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
    assert_success "$(post '{"action": "calibrate"}')" "calibrate"
}

test_eval() {
    assert_success "$(post '{"action": "eval", "expression": "document.title"}')" "eval"
}

test_screenshot_browser() {
    assert_http_ok "$BASE/screenshot/browser" "screenshot/browser"
}

test_screenshot_desktop() {
    assert_http_ok "$BASE/screenshot/desktop" "screenshot/desktop"
}

test_state() {
    local resp
    resp=$(curl -sf "$BASE/state")
    if ! echo "$resp" | grep -q '"status"'; then
        echo "FAIL: state: $resp"
        return 1
    fi
    echo "OK: state"
}

test_health() {
    assert_http_ok "$BASE/health" "health"
}

test_mouse_move() {
    assert_success "$(post '{"action": "mouse_move", "x": 100, "y": 100, "duration": 0.1}')" "mouse_move"
}

test_mouse_click() {
    assert_success "$(post '{"action": "mouse_click", "x": 100, "y": 100}')" "mouse_click"
}

test_system_click() {
    assert_success "$(post '{"action": "system_click", "x": 100, "y": 100}')" "system_click"
}

test_scroll() {
    assert_success "$(post '{"action": "scroll", "amount": -3}')" "scroll"
}

test_system_type() {
    assert_success "$(post '{"action": "system_type", "text": "test", "interval": 0.02}')" "system_type"
}

test_send_key() {
    assert_success "$(post '{"action": "send_key", "key": "escape"}')" "send_key"
}

test_enter_fullscreen() {
    assert_success "$(post '{"action": "enter_fullscreen"}')" "enter_fullscreen"
}

test_exit_fullscreen() {
    assert_success "$(post '{"action": "exit_fullscreen"}')" "exit_fullscreen"
}

test_fill() {
    post '{"action": "goto", "url": "https://www.google.com"}' >/dev/null
    sleep 1
    assert_success "$(post '{"action": "fill", "selector": "textarea[name=q]", "value": "test"}')" "fill"
}

test_type_action() {
    post '{"action": "goto", "url": "https://www.google.com"}' >/dev/null
    sleep 1
    assert_success "$(post '{"action": "type", "selector": "textarea[name=q]", "text": "test", "delay": 0.02}')" "type"
}

test_click() {
    assert_success "$(post '{"action": "click", "selector": "body"}')" "click"
}

# --- Env var tests (spawn separate containers) ---

test_xvfb_resolution_env() {
    # Verify XVFB_RESOLUTION env var sets the display resolution at startup.
    # Checks: desktop screenshot dimensions, API response, and JS-reported screen size.
    local name="${CONTAINER_NAME}-xvfb-res"
    local tmpdir="$TESTDATA_DIR/xvfb-res-screenshots"
    mkdir -p "$tmpdir"

    local ip base
    ip=$(start_extra_container "$name" \
        -e "XVFB_RESOLUTION=1280x720")
    base="http://${ip}:${INTERNAL_PORT}"

    if ! wait_for_api "$base" 90; then
        echo "FAIL: xvfb_resolution_env: API not ready"
        docker logs "$name" 2>&1 | tail -20
        stop_extra_container "$name"
        return 1
    fi

    # Inject test HTML and navigate to it
    inject_test_html "$name"
    post_to "$base" '{"action": "goto", "url": "file:///tmp/resolution_test.html"}' >/dev/null
    sleep 1

    # Verify screen dimensions via JS eval
    local resp js_screen_w js_screen_h
    resp=$(post_to "$base" '{"action": "eval", "expression": "screen.width"}')
    js_screen_w=$(echo "$resp" | json_get "['data']['result']")
    resp=$(post_to "$base" '{"action": "eval", "expression": "screen.height"}')
    js_screen_h=$(echo "$resp" | json_get "['data']['result']")
    assert_eq "$js_screen_w" "1280" "xvfb_resolution_env: JS screen.width" || { stop_extra_container "$name"; return 1; }
    assert_eq "$js_screen_h" "720" "xvfb_resolution_env: JS screen.height" || { stop_extra_container "$name"; return 1; }

    # Take desktop screenshot and verify pixel dimensions
    curl -sf "$base/screenshot/desktop" -o "$tmpdir/desktop_1280x720.png"
    local dims
    dims=$(png_dimensions "$tmpdir/desktop_1280x720.png")
    assert_eq "$dims" "1280x720" "xvfb_resolution_env: desktop screenshot" || { stop_extra_container "$name"; return 1; }

    # Verify get_resolution API reports correct values
    local w h
    resp=$(post_to "$base" '{"action": "get_resolution"}')
    w=$(echo "$resp" | json_get "['data']['width']")
    h=$(echo "$resp" | json_get "['data']['height']")
    assert_eq "$w" "1280" "xvfb_resolution_env: API width" || { stop_extra_container "$name"; return 1; }
    assert_eq "$h" "720" "xvfb_resolution_env: API height" || { stop_extra_container "$name"; return 1; }

    stop_extra_container "$name"
    echo "OK: xvfb_resolution_env (JS screen 1280x720, desktop screenshot 1280x720, API 1280x720)"
}

test_use_viewport_env() {
    # USE_VIEWPORT=true with custom XVFB_RESOLUTION.
    # Checks: browser screenshot, desktop screenshot, JS-reported dimensions.
    local name="${CONTAINER_NAME}-viewport-env"
    local tmpdir="$TESTDATA_DIR/viewport-env-screenshots"
    mkdir -p "$tmpdir"

    local ip base
    ip=$(start_extra_container "$name" \
        -e USE_VIEWPORT=true \
        -e "XVFB_RESOLUTION=800x600")
    base="http://${ip}:${INTERNAL_PORT}"

    if ! wait_for_api "$base" 90; then
        echo "FAIL: use_viewport_env: API not ready"
        docker logs "$name" 2>&1 | tail -20
        stop_extra_container "$name"
        return 1
    fi

    # Inject test HTML and navigate to it
    inject_test_html "$name"
    post_to "$base" '{"action": "goto", "url": "file:///tmp/resolution_test.html"}' >/dev/null
    sleep 1

    # Verify JS reports 800x600 screen
    local resp js_screen_w js_screen_h
    resp=$(post_to "$base" '{"action": "eval", "expression": "screen.width"}')
    js_screen_w=$(echo "$resp" | json_get "['data']['result']")
    resp=$(post_to "$base" '{"action": "eval", "expression": "screen.height"}')
    js_screen_h=$(echo "$resp" | json_get "['data']['result']")
    assert_eq "$js_screen_w" "800" "use_viewport_env: JS screen.width" || { stop_extra_container "$name"; return 1; }
    assert_eq "$js_screen_h" "600" "use_viewport_env: JS screen.height" || { stop_extra_container "$name"; return 1; }

    # Browser screenshot should be 800x600
    curl -sf "$base/screenshot/browser" -o "$tmpdir/browser_800x600.png"
    local browser_dims
    browser_dims=$(png_dimensions "$tmpdir/browser_800x600.png")
    assert_eq "$browser_dims" "800x600" "use_viewport_env: browser screenshot" || { stop_extra_container "$name"; return 1; }

    # Desktop screenshot should also be 800x600
    curl -sf "$base/screenshot/desktop" -o "$tmpdir/desktop_800x600.png"
    local desktop_dims
    desktop_dims=$(png_dimensions "$tmpdir/desktop_800x600.png")
    assert_eq "$desktop_dims" "800x600" "use_viewport_env: desktop screenshot" || { stop_extra_container "$name"; return 1; }

    stop_extra_container "$name"
    echo "OK: use_viewport_env (JS screen 800x600, browser screenshot 800x600, desktop screenshot 800x600)"
}

test_phone_viewport_env() {
    # Phone-sized viewport with USE_VIEWPORT=true.
    # Firefox has a ~450px min without viewport control, so this tests that path.
    local name="${CONTAINER_NAME}-phone-env"
    local tmpdir="$TESTDATA_DIR/phone-env-screenshots"
    mkdir -p "$tmpdir"

    local ip base
    ip=$(start_extra_container "$name" \
        -e USE_VIEWPORT=true \
        -e "XVFB_RESOLUTION=375x812")
    base="http://${ip}:${INTERNAL_PORT}"

    if ! wait_for_api "$base" 90; then
        echo "FAIL: phone_viewport_env: API not ready"
        docker logs "$name" 2>&1 | tail -20
        stop_extra_container "$name"
        return 1
    fi

    # Inject test HTML and navigate to it
    inject_test_html "$name"
    post_to "$base" '{"action": "goto", "url": "file:///tmp/resolution_test.html"}' >/dev/null
    sleep 1

    # Verify JS reports 375x812 screen
    local resp js_screen_w js_screen_h
    resp=$(post_to "$base" '{"action": "eval", "expression": "screen.width"}')
    js_screen_w=$(echo "$resp" | json_get "['data']['result']")
    resp=$(post_to "$base" '{"action": "eval", "expression": "screen.height"}')
    js_screen_h=$(echo "$resp" | json_get "['data']['result']")
    assert_eq "$js_screen_w" "375" "phone_viewport_env: JS screen.width" || { stop_extra_container "$name"; return 1; }
    assert_eq "$js_screen_h" "812" "phone_viewport_env: JS screen.height" || { stop_extra_container "$name"; return 1; }

    # Browser screenshot should be 375x812
    curl -sf "$base/screenshot/browser" -o "$tmpdir/browser_375x812.png"
    local browser_dims
    browser_dims=$(png_dimensions "$tmpdir/browser_375x812.png")
    assert_eq "$browser_dims" "375x812" "phone_viewport_env: browser screenshot" || { stop_extra_container "$name"; return 1; }

    stop_extra_container "$name"
    echo "OK: phone_viewport_env (JS screen 375x812, browser screenshot 375x812)"
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
    test_xvfb_resolution_env
    test_use_viewport_env
    test_phone_viewport_env
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
    if $t; then
        PASSED=$((PASSED + 1))
        continue
    fi
    FAILED=$((FAILED + 1))
done

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
