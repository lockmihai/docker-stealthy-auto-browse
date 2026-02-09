#!/bin/bash
# tests/test_waits.sh - Wait condition tests

test_wait_for_element() {
    local resp

    # Wait for existing element (CSS selector)
    resp=$(post '{"action": "wait_for_element", "selector": "#submit-btn", "timeout": 5}')
    assert_success "$resp" "wait_for_element: CSS selector" || return 1

    # Wait for existing element (XPath)
    resp=$(post '{"action": "wait_for_element", "selector": "xpath=//button[@id=\"submit-btn\"]", "timeout": 5}')
    assert_success "$resp" "wait_for_element: XPath" || return 1

    echo "OK: wait_for_element (CSS + XPath)"
}

test_wait_for_text() {
    local resp

    # The test fixture has "Submit" text on the button
    resp=$(post '{"action": "wait_for_text", "text": "Submit", "timeout": 5}')
    assert_success "$resp" "wait_for_text" || return 1
    echo "OK: wait_for_text (found 'Submit')"
}

test_wait_for_url() {
    local resp

    # We're already on index.html
    resp=$(post '{"action": "wait_for_url", "url": "**/index.html", "timeout": 5}')
    assert_success "$resp" "wait_for_url" || return 1
    echo "OK: wait_for_url (matched index.html)"
}

test_wait_for_network_idle() {
    local resp

    # Page is already loaded, should be idle
    resp=$(post '{"action": "wait_for_network_idle", "timeout": 10}')
    assert_success "$resp" "wait_for_network_idle" || return 1
    echo "OK: wait_for_network_idle"
}

ALL_TESTS+=(
    test_wait_for_element
    test_wait_for_text
    test_wait_for_url
    test_wait_for_network_idle
)
