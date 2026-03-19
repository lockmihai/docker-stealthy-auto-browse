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

test_goto_referer() {
    local referer_url="${WEB_BASE}/referer"
    local fake_referer="https://www.google.com/search?q=test"

    # goto with referer
    local resp
    resp=$(post "{\"action\": \"goto\", \"url\": \"$referer_url\", \"referer\": \"$fake_referer\"}")
    assert_success "$resp" "goto_referer: goto success" || return 1

    # Page should show JSON with our referer
    local text
    text=$(post '{"action": "get_text"}')
    local got_referer
    got_referer=$(echo "$text" | python3 -c "import sys,json; t=json.load(sys.stdin)['data']['text']; d=json.loads(t); print(d['referer'])")
    assert_eq "$got_referer" "$fake_referer" "goto_referer: referer matches" || return 1

    echo "OK: goto_referer (referer=$fake_referer)"
}

test_goto_no_referer() {
    local referer_url="${WEB_BASE}/referer"

    # goto without referer
    local resp
    resp=$(post "{\"action\": \"goto\", \"url\": \"$referer_url\"}")
    assert_success "$resp" "goto_no_referer: goto success" || return 1

    # Referer should be empty
    local text
    text=$(post '{"action": "get_text"}')
    local got_referer
    got_referer=$(echo "$text" | python3 -c "import sys,json; t=json.load(sys.stdin)['data']['text']; d=json.loads(t); print(d['referer'])")
    assert_eq "$got_referer" "" "goto_no_referer: referer empty" || return 1

    echo "OK: goto_no_referer (no referer sent)"
}

ALL_TESTS+=(
    test_refresh
    test_refresh_wait_until
    test_goto_referer
    test_goto_no_referer
)
