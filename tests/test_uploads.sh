#!/bin/bash
# tests/test_uploads.sh - File upload tests

test_upload_file() {
    local resp filename file_size expected_size

    # Copy the upload fixture into the browser container
    docker cp "$FIXTURES_DIR/upload.txt" "${CONTAINER_NAME}:/tmp/upload.txt"
    expected_size=$(wc -c < "$FIXTURES_DIR/upload.txt" | tr -d ' ')

    # Navigate to test page (has upload form)
    post "{\"action\": \"goto\", \"url\": \"$TEST_PAGE\"}" >/dev/null
    sleep 1

    # Set file on the file input
    resp=$(post '{"action": "upload_file", "selector": "#file-input", "file_path": "/tmp/upload.txt"}')
    assert_success "$resp" "upload_file: set file" || return 1
    filename=$(echo "$resp" | json_get "['data']['file']")
    assert_eq "$filename" "upload.txt" "upload_file: filename in response" || return 1
    file_size=$(echo "$resp" | json_get "['data']['size']")
    assert_eq "$file_size" "$expected_size" "upload_file: size in response" || return 1

    # Rewrite form action to point to the web server
    post "{\"action\": \"eval\", \"expression\": \"document.getElementById('upload-form').action = '$WEB_BASE/upload'\"}" >/dev/null

    # Submit the form
    resp=$(post '{"action": "click", "selector": "#upload-btn"}')
    assert_success "$resp" "upload_file: submit form" || return 1
    sleep 2

    # The browser navigated to the server's JSON response — read it
    resp=$(post '{"action": "get_text"}')
    assert_success "$resp" "upload_file: get server response" || return 1
    local server_resp
    server_resp=$(echo "$resp" | json_get "['data']['text']")

    # Verify server response fields
    local srv_filename srv_size
    srv_filename=$(echo "$server_resp" | python3 -c "import sys,json; print(json.load(sys.stdin)['filename'])")
    srv_size=$(echo "$server_resp" | python3 -c "import sys,json; print(json.load(sys.stdin)['size'])")
    assert_eq "$srv_filename" "upload.txt" "upload_file: server got filename" || return 1
    assert_eq "$srv_size" "$expected_size" "upload_file: server got size" || return 1

    # Verify the uploaded file is accessible and content matches
    local uploaded_content expected_content
    uploaded_content=$(curl -sf "$WEB_BASE/uploads/upload.txt")
    if [ -z "$uploaded_content" ]; then
        echo "FAIL: upload_file: uploaded file not accessible on server"
        return 1
    fi
    expected_content=$(cat "$FIXTURES_DIR/upload.txt")
    assert_eq "$uploaded_content" "$expected_content" "upload_file: content matches" || return 1

    echo "OK: upload_file (set file, submitted, server confirmed, content verified)"
}

ALL_TESTS+=(test_upload_file)
