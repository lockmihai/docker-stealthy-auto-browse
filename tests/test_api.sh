#!/bin/bash
# tests/test_api.sh - Basic API endpoint tests

test_ping() {
    local resp msg
    resp=$(post '{"action": "ping"}')
    assert_success "$resp" "ping" || return 1
    msg=$(echo "$resp" | json_get "['data']['message']")
    assert_eq "$msg" "pong" "ping: message"
}

test_goto() {
    local resp title
    resp=$(post "{\"action\": \"goto\", \"url\": \"$TEST_PAGE\"}")
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

ALL_TESTS+=(
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
)
