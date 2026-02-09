#!/bin/bash
# tests/test_network.sh - Network request logging tests

test_network_log() {
    local resp count

    # Enable logging
    resp=$(post '{"action": "enable_network_log"}')
    assert_success "$resp" "network_log: enable" || return 1

    # Clear any existing entries
    post '{"action": "clear_network_log"}' >/dev/null

    # Navigate to the web server (real HTTP traffic)
    post "{\"action\": \"goto\", \"url\": \"$TEST_PAGE\", \"wait_until\": \"domcontentloaded\"}" >/dev/null
    sleep 1

    # Get the log
    resp=$(post '{"action": "get_network_log"}')
    assert_success "$resp" "network_log: get" || return 1
    count=$(echo "$resp" | json_get "['data']['count']")
    if [ "$count" -lt 1 ]; then
        echo "FAIL: network_log: expected >= 1 entries, got $count"
        return 1
    fi

    # Verify log has request/response entries
    local has_request has_response
    has_request=$(echo "$resp" | python3 -c "
import sys, json
log = json.load(sys.stdin)['data']['log']
print(any(e['type'] == 'request' for e in log))
")
    has_response=$(echo "$resp" | python3 -c "
import sys, json
log = json.load(sys.stdin)['data']['log']
print(any(e['type'] == 'response' for e in log))
")
    assert_eq "$has_request" "True" "network_log: has requests" || return 1
    assert_eq "$has_response" "True" "network_log: has responses" || return 1

    # Clear the log
    resp=$(post '{"action": "clear_network_log"}')
    assert_success "$resp" "network_log: clear" || return 1

    # Verify it's empty
    resp=$(post '{"action": "get_network_log"}')
    count=$(echo "$resp" | json_get "['data']['count']")
    assert_eq "$count" "0" "network_log: cleared" || return 1

    # Disable logging
    resp=$(post '{"action": "disable_network_log"}')
    assert_success "$resp" "network_log: disable" || return 1

    echo "OK: network_log (enable, capture, clear, disable)"
}

ALL_TESTS+=(test_network_log)
