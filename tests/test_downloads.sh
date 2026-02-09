#!/bin/bash
# tests/test_downloads.sh - File download tests

test_download() {
    local resp filename

    # No download yet
    resp=$(post '{"action": "get_last_download"}')
    assert_success "$resp" "download: initial state" || return 1

    # Click the download link in our test fixture
    resp=$(post '{"action": "click", "selector": "#download-link"}')
    assert_success "$resp" "download: click link" || return 1

    # Give the download a moment
    sleep 2

    # Check download was tracked
    resp=$(post '{"action": "get_last_download"}')
    assert_success "$resp" "download: get_last_download" || return 1
    filename=$(echo "$resp" | json_get "['data']['download']['filename']")
    assert_eq "$filename" "download.txt" "download: filename" || return 1
    echo "OK: download (filename=$filename)"
}

ALL_TESTS+=(test_download)
