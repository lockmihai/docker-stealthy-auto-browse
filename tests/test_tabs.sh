#!/bin/bash
# tests/test_tabs.sh - Tab management tests

test_list_tabs() {
    local resp count
    resp=$(post '{"action": "list_tabs"}')
    assert_success "$resp" "list_tabs" || return 1
    count=$(echo "$resp" | json_get "['data']['count']")
    if [ "$count" -lt 1 ]; then
        echo "FAIL: list_tabs: expected >= 1 tab, got $count"
        return 1
    fi
    echo "OK: list_tabs (count=$count)"
}

test_new_tab() {
    local resp index count

    # Open new tab with URL
    resp=$(post "{\"action\": \"new_tab\", \"url\": \"$TEST_PAGE\"}")
    assert_success "$resp" "new_tab" || return 1
    index=$(echo "$resp" | json_get "['data']['index']")

    # Should now have 2+ tabs
    resp=$(post '{"action": "list_tabs"}')
    count=$(echo "$resp" | json_get "['data']['count']")
    if [ "$count" -lt 2 ]; then
        echo "FAIL: new_tab: expected >= 2 tabs, got $count"
        return 1
    fi
    echo "OK: new_tab (index=$index, total=$count)"
}

test_switch_tab() {
    local resp url

    # Switch to first tab (index 0)
    resp=$(post '{"action": "switch_tab", "index": 0}')
    assert_success "$resp" "switch_tab: to 0" || return 1

    # Verify it's active
    resp=$(post '{"action": "list_tabs"}')
    local active
    active=$(echo "$resp" | python3 -c "
import sys, json
tabs = json.load(sys.stdin)['data']['tabs']
for t in tabs:
    if t['active']:
        print(t['index'])
        break
")
    assert_eq "$active" "0" "switch_tab: active index" || return 1
    echo "OK: switch_tab (switched to tab 0)"
}

test_close_tab() {
    local resp remaining

    # Get current tab count
    resp=$(post '{"action": "list_tabs"}')
    local before
    before=$(echo "$resp" | json_get "['data']['count']")

    # Open a tab then close it
    post '{"action": "new_tab"}' >/dev/null
    resp=$(post '{"action": "close_tab"}')
    assert_success "$resp" "close_tab" || return 1
    remaining=$(echo "$resp" | json_get "['data']['remaining']")
    assert_eq "$remaining" "$before" "close_tab: remaining count" || return 1
    echo "OK: close_tab (remaining=$remaining)"
}

ALL_TESTS+=(
    test_list_tabs
    test_new_tab
    test_switch_tab
    test_close_tab
)
