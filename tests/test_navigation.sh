#!/bin/bash
# tests/test_navigation.sh - Tests for navigation actions

test_refresh() {
    local resp url title

    resp=$(post '{"action": "refresh"}')
    assert_success "$resp" "refresh" || return 1

    url=$(echo "$resp" | json_get "['data']['url']")
    echo "$url" | grep -q "index.html" || { echo "  FAIL: refresh: expected index.html in URL, got $url"; return 1; }

    title=$(echo "$resp" | json_get "['data']['title']")
    assert_eq "$title" "Test Page" "refresh: title" || return 1
    echo "  OK: refresh (url=$url, title=$title)"
}

test_refresh_wait_until() {
    local resp url

    resp=$(post '{"action": "refresh", "wait_until": "load"}')
    assert_success "$resp" "refresh with wait_until=load" || return 1

    url=$(echo "$resp" | json_get "['data']['url']")
    echo "$url" | grep -q "index.html" || { echo "  FAIL: refresh_wait_until: expected index.html, got $url"; return 1; }
    echo "  OK: refresh with wait_until=load (url=$url)"
}

ALL_TESTS+=(
    test_refresh
    test_refresh_wait_until
)
