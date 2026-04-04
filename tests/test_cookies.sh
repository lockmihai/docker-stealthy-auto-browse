#!/bin/bash
# tests/test_cookies.sh - Cookie and storage management tests

test_set_get_cookies() {
    local resp count name

    # Set a cookie
    resp=$(post "{\"action\": \"set_cookie\", \"name\": \"test_cookie\", \"value\": \"hello123\", \"url\": \"$TEST_PAGE\"}")
    assert_success "$resp" "set_cookie" || return 1

    # Get cookies
    resp=$(post '{"action": "get_cookies"}')
    assert_success "$resp" "get_cookies" || return 1
    count=$(echo "$resp" | json_get "['data']['count']")
    if [ "$count" -lt 1 ]; then
        echo "FAIL: get_cookies: expected >= 1, got $count"
        return 1
    fi

    # Find our cookie
    name=$(echo "$resp" | python3 -c "
import sys, json
cookies = json.load(sys.stdin)['data']['cookies']
for c in cookies:
    if c['name'] == 'test_cookie':
        print(c['value'])
        break
")
    assert_eq "$name" "hello123" "get_cookies: value" || return 1
    echo "OK: set_get_cookies (value=$name)"
}

test_delete_cookies() {
    local resp count

    # Delete all cookies
    resp=$(post '{"action": "delete_cookies"}')
    assert_success "$resp" "delete_cookies" || return 1

    # Verify empty
    resp=$(post '{"action": "get_cookies"}')
    count=$(echo "$resp" | json_get "['data']['count']")
    assert_eq "$count" "0" "delete_cookies: count" || return 1
    echo "OK: delete_cookies (count=0)"
}

# --- Table-driven storage tests ---
# Each case: "type|set_key|set_val"
STORAGE_CASES=(
    "local|test_key|test_val"
    "session|sess_key|sess_val"
)

_run_storage_case() {
    local stype="$1" key="$2" val="$3"
    local resp got

    # Set
    resp=$(post "{\"action\": \"set_storage\", \"type\": \"$stype\", \"key\": \"$key\", \"value\": \"$val\"}")
    assert_success "$resp" "set_storage: $stype" || return 1

    # Get and verify value
    resp=$(post "{\"action\": \"get_storage\", \"type\": \"$stype\"}")
    assert_success "$resp" "get_storage: $stype" || return 1
    got=$(echo "$resp" | json_get "['data']['items']['$key']")
    assert_eq "$got" "$val" "get_storage: $stype value" || return 1

    # Clear
    resp=$(post "{\"action\": \"clear_storage\", \"type\": \"$stype\"}")
    assert_success "$resp" "clear_storage: $stype" || return 1

    # Verify empty
    resp=$(post "{\"action\": \"get_storage\", \"type\": \"$stype\"}")
    got=$(echo "$resp" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['data']['items']))")
    assert_eq "$got" "0" "clear_storage: $stype empty" || return 1

    echo "  - $stype: OK (set, get, clear)"
}

test_storage() {
    local entry stype key val
    for entry in "${STORAGE_CASES[@]}"; do
        IFS='|' read -r stype key val <<< "$entry"
        _run_storage_case "$stype" "$key" "$val" || return 1
    done
    echo "OK: storage (${#STORAGE_CASES[@]} types passed)"
}

ALL_TESTS+=(
    test_set_get_cookies
    test_delete_cookies
    test_storage
)
