#!/bin/bash
# tests/common.sh - Shared helpers, variables, and infrastructure for the test suite.
# Sourced by test.sh; not meant to be run directly.

IMAGE_NAME="psyb0t/stealthy-auto-browse"
TEST_TAG="latest-test"
CONTAINER_NAME="stealthy-auto-browse-test"
WEBSERVER_NAME="stealthy-auto-browse-test-web"
INTERNAL_PORT="8080"
BASE=""
WEB_BASE=""
WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTDATA_DIR="$WORKDIR/.testdata"
FIXTURES_DIR="$WORKDIR/tests/fixtures"
RESULTS_DIR="$WORKDIR/tests/results"

# Track extra containers for cleanup
EXTRA_CONTAINERS=()

# URL to the test fixture page (set after web server starts)
TEST_PAGE=""

# All test names - each test file appends to this
ALL_TESTS=()

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
    if ! echo "$resp" | grep -qE '"success":\s*true'; then
        echo "  FAIL: $name: $resp"
        return 1
    fi
    echo "  OK: $name"
}

assert_http_ok() {
    local url="$1"
    local name="$2"
    local code
    code=$(curl -sf -o /dev/null -w "%{http_code}" "$url")
    if [ "$code" != "200" ]; then
        echo "  FAIL: $name: HTTP $code"
        return 1
    fi
    echo "  OK: $name"
}

assert_eq() {
    local actual="$1"
    local expected="$2"
    local name="$3"
    if [ "$actual" != "$expected" ]; then
        echo "  FAIL: $name: expected $expected, got $actual"
        return 1
    fi
}

start_extra_container() {
    local name="$1"
    shift
    docker rm -f "$name" >/dev/null 2>&1 || true
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

wait_for_server() {
    local url="$1"
    local max_wait="${2:-20}"
    for i in $(seq 1 "$max_wait"); do
        if curl -sf "$url" >/dev/null 2>&1; then
            return 0
        fi
        if [ "$i" -eq "$max_wait" ]; then
            return 1
        fi
        sleep 1
    done
}

stop_extra_container() {
    local name="$1"
    docker rm -f "$name" >/dev/null 2>&1 || true
}

# --- Per-test setup/teardown (main container only) ---

test_setup() {
    post "{\"action\": \"goto\", \"url\": \"$TEST_PAGE\"}" >/dev/null
    sleep 1
}

test_teardown() {
    # Reset scroll position
    post '{"action": "eval", "expression": "window.scrollTo(0,0)"}' >/dev/null 2>&1 || true
    # Exit fullscreen if active
    post '{"action": "exit_fullscreen"}' >/dev/null 2>&1 || true
}

# --- Infrastructure setup ---

setup() {
    # Prepare testdata dir
    rm -rf "$TESTDATA_DIR" 2>/dev/null || true
    mkdir -p "$TESTDATA_DIR"

    # Prepare results dir
    mkdir -p "$RESULTS_DIR"

    # Build test image
    echo "Building test image..."
    docker build -t "$IMAGE_NAME:$TEST_TAG" .

    # --- Start web server for fixtures ---
    echo "Starting web server..."
    docker rm -f "$WEBSERVER_NAME" >/dev/null 2>&1 || true
    docker run -d --name "$WEBSERVER_NAME" \
        -v "$FIXTURES_DIR:/srv:ro" \
        -v "$WORKDIR/tests/apps/http_server.py:/server.py:ro" \
        python:3.12-slim python /server.py 80 /srv >/dev/null
    EXTRA_CONTAINERS+=("$WEBSERVER_NAME")

    local web_ip
    web_ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$WEBSERVER_NAME")
    WEB_BASE="http://${web_ip}"
    TEST_PAGE="${WEB_BASE}/index.html"

    if ! wait_for_server "$TEST_PAGE" 20; then
        echo "FAIL: Web server did not become ready"
        docker logs "$WEBSERVER_NAME" 2>&1 | tail -10
        exit 1
    fi
    echo "Web server ready at $WEB_BASE"

    # --- Start main browser container ---
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

    echo "Starting test container..."
    docker run -d --name "$CONTAINER_NAME" "$IMAGE_NAME:$TEST_TAG"

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
        docker rm -f "$c" >/dev/null 2>&1 || true
    done
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
    docker rmi "$IMAGE_NAME:$TEST_TAG" 2>/dev/null || true
    rm -rf "$TESTDATA_DIR" 2>/dev/null || true
}

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
