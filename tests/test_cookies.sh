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

test_local_storage() {
    local resp val

    # Set localStorage
    resp=$(post '{"action": "set_storage", "type": "local", "key": "test_key", "value": "test_val"}')
    assert_success "$resp" "set_storage: local" || return 1

    # Get localStorage
    resp=$(post '{"action": "get_storage", "type": "local"}')
    assert_success "$resp" "get_storage: local" || return 1
    val=$(echo "$resp" | json_get "['data']['items']['test_key']")
    assert_eq "$val" "test_val" "get_storage: local value" || return 1

    # Clear localStorage
    resp=$(post '{"action": "clear_storage", "type": "local"}')
    assert_success "$resp" "clear_storage: local" || return 1

    # Verify empty
    resp=$(post '{"action": "get_storage", "type": "local"}')
    val=$(echo "$resp" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['data']['items']))")
    assert_eq "$val" "0" "clear_storage: local empty" || return 1
    echo "OK: local_storage (set, get, clear)"
}

test_session_storage() {
    local resp val

    # Set sessionStorage
    resp=$(post '{"action": "set_storage", "type": "session", "key": "sess_key", "value": "sess_val"}')
    assert_success "$resp" "set_storage: session" || return 1

    # Get sessionStorage
    resp=$(post '{"action": "get_storage", "type": "session"}')
    assert_success "$resp" "get_storage: session" || return 1
    val=$(echo "$resp" | json_get "['data']['items']['sess_key']")
    assert_eq "$val" "sess_val" "get_storage: session value" || return 1

    # Clear sessionStorage
    resp=$(post '{"action": "clear_storage", "type": "session"}')
    assert_success "$resp" "clear_storage: session" || return 1
    echo "OK: session_storage (set, get, clear)"
}

ALL_TESTS+=(
    test_set_get_cookies
    test_delete_cookies
    test_local_storage
    test_session_storage
)
