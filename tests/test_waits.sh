#!/bin/bash
# tests/test_waits.sh - Wait condition tests

# Each case: "label|action_json"
WAIT_CASES=(
    'wait_for_element CSS|{"action": "wait_for_element", "selector": "#submit-btn", "timeout": 5}'
    'wait_for_element XPath|{"action": "wait_for_element", "selector": "xpath=//button[@id=\"submit-btn\"]", "timeout": 5}'
    'wait_for_text|{"action": "wait_for_text", "text": "Submit", "timeout": 5}'
    'wait_for_url|{"action": "wait_for_url", "url": "**/index.html", "timeout": 5}'
    'wait_for_network_idle|{"action": "wait_for_network_idle", "timeout": 10}'
)

test_waits() {
    local entry label action_json resp
    for entry in "${WAIT_CASES[@]}"; do
        IFS='|' read -r label action_json <<< "$entry"
        resp=$(post "$action_json")
        assert_success "$resp" "$label" || return 1
    done
    echo "OK: waits (${#WAIT_CASES[@]} cases passed)"
}

ALL_TESTS+=(test_waits)
