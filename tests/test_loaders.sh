#!/bin/bash
# tests/test_loaders.sh - URL-triggered page loader tests

LOADER_FIXTURES="$WORKDIR/tests/fixtures/loaders"

_loader_container_name="${CONTAINER_NAME}-loaders"
_loader_base=""

_loader_setup() {
    local ip
    ip=$(start_extra_container "$_loader_container_name" \
        -v "$LOADER_FIXTURES:/loaders")
    _loader_base="http://${ip}:${INTERNAL_PORT}"

    if ! wait_for_api "$_loader_base" 90; then
        echo "FAIL: loader setup: API not ready"
        docker logs "$_loader_container_name" 2>&1 | tail -20
        stop_extra_container "$_loader_container_name"
        return 1
    fi
}

_loader_teardown() {
    stop_extra_container "$_loader_container_name"
}

test_loader_match() {
    _loader_setup || return 1

    # goto matching URL - should trigger the loader
    local resp
    resp=$(post_to "$_loader_base" "{\"action\": \"goto\", \"url\": \"$TEST_PAGE\"}")
    assert_success "$resp" "loader_match: goto success" || { _loader_teardown; return 1; }

    # Response should contain loader metadata
    local loader_name
    loader_name=$(echo "$resp" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['loader'])" 2>/dev/null)
    if [ -z "$loader_name" ]; then
        echo "FAIL: loader_match: response missing 'loader' key in data"
        echo "  response: $resp"
        _loader_teardown
        return 1
    fi
    assert_eq "$loader_name" "Test Fixture Loader" "loader_match: loader name" || { _loader_teardown; return 1; }

    # Verify loader's eval step actually ran (set #loader-marker text)
    local marker
    resp=$(post_to "$_loader_base" '{"action": "eval", "expression": "document.getElementById(\"loader-marker\").textContent"}')
    marker=$(echo "$resp" | json_get "['data']['result']")
    assert_eq "$marker" "loader-executed" "loader_match: marker set by loader" || { _loader_teardown; return 1; }

    _loader_teardown
    echo "OK: loader_match (loader triggered, marker set)"
}

test_loader_no_match() {
    _loader_setup || return 1

    # goto non-matching URL - should be a normal goto
    local resp
    resp=$(post_to "$_loader_base" '{"action": "goto", "url": "about:blank"}')
    assert_success "$resp" "loader_no_match: goto success" || { _loader_teardown; return 1; }

    # Response should NOT contain loader metadata (it's a plain goto response)
    local has_loader
    has_loader=$(echo "$resp" | python3 -c "import sys,json; d=json.load(sys.stdin).get('data',{}); print('yes' if 'loader' in d else 'no')" 2>/dev/null)
    if [ "$has_loader" = "yes" ]; then
        echo "FAIL: loader_no_match: response unexpectedly has 'loader' key"
        echo "  response: $resp"
        _loader_teardown
        return 1
    fi

    _loader_teardown
    echo "OK: loader_no_match (normal goto, no loader triggered)"
}

ALL_TESTS+=(
    test_loader_match
    test_loader_no_match
)
