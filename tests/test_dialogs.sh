#!/bin/bash
# tests/test_dialogs.sh - Dialog handling tests (alert, confirm, prompt)

test_dialog_alert() {
    local resp dtype msg buttons

    # No dialog yet
    resp=$(post '{"action": "get_last_dialog"}')
    assert_success "$resp" "dialog_alert: get_last_dialog before" || return 1

    # Trigger alert (auto-accepted)
    resp=$(post '{"action": "eval", "expression": "alert(1234)"}')
    assert_success "$resp" "dialog_alert: eval alert" || return 1

    # Check captured dialog
    resp=$(post '{"action": "get_last_dialog"}')
    assert_success "$resp" "dialog_alert: get_last_dialog after" || return 1
    dtype=$(echo "$resp" | json_get "['data']['dialog']['type']")
    msg=$(echo "$resp" | json_get "['data']['dialog']['message']")
    buttons=$(echo "$resp" | json_get "['data']['dialog']['buttons']")
    assert_eq "$dtype" "alert" "dialog_alert: type" || return 1
    assert_eq "$msg" "1234" "dialog_alert: message" || return 1
    echo "$buttons" | grep -q "ok" || { echo "FAIL: dialog_alert: missing ok button"; return 1; }
    echo "OK: dialog_alert (type=$dtype, message=$msg, buttons=$buttons)"
}

test_dialog_confirm_accept() {
    local resp result dtype

    # Default: auto-accept
    resp=$(post '{"action": "eval", "expression": "confirm(\"Accept me\")"}')
    assert_success "$resp" "dialog_confirm_accept: eval" || return 1
    result=$(echo "$resp" | json_get "['data']['result']")
    assert_eq "$result" "True" "dialog_confirm_accept: result" || return 1

    resp=$(post '{"action": "get_last_dialog"}')
    dtype=$(echo "$resp" | json_get "['data']['dialog']['type']")
    assert_eq "$dtype" "confirm" "dialog_confirm_accept: type" || return 1
    echo "OK: dialog_confirm_accept (result=$result)"
}

test_dialog_confirm_dismiss() {
    local resp result

    # Pre-configure dismiss
    resp=$(post '{"action": "handle_dialog", "accept": false}')
    assert_success "$resp" "dialog_confirm_dismiss: handle_dialog" || return 1

    resp=$(post '{"action": "eval", "expression": "confirm(\"Dismiss me\")"}')
    assert_success "$resp" "dialog_confirm_dismiss: eval" || return 1
    result=$(echo "$resp" | json_get "['data']['result']")
    assert_eq "$result" "False" "dialog_confirm_dismiss: result" || return 1
    echo "OK: dialog_confirm_dismiss (result=$result)"
}

test_dialog_prompt_accept_text() {
    local resp result msg

    # Pre-configure accept with custom text
    resp=$(post '{"action": "handle_dialog", "accept": true, "text": "hello"}')
    assert_success "$resp" "dialog_prompt_accept: handle_dialog" || return 1

    resp=$(post '{"action": "eval", "expression": "prompt(\"Name?\", \"default\")"}')
    assert_success "$resp" "dialog_prompt_accept: eval" || return 1
    result=$(echo "$resp" | json_get "['data']['result']")
    assert_eq "$result" "hello" "dialog_prompt_accept: result" || return 1

    # Verify captured info
    resp=$(post '{"action": "get_last_dialog"}')
    msg=$(echo "$resp" | json_get "['data']['dialog']['message']")
    assert_eq "$msg" "Name?" "dialog_prompt_accept: message" || return 1
    echo "OK: dialog_prompt_accept (result=$result)"
}

test_dialog_prompt_dismiss() {
    local resp result

    # Pre-configure dismiss (cancel button)
    resp=$(post '{"action": "handle_dialog", "accept": false}')
    assert_success "$resp" "dialog_prompt_dismiss: handle_dialog" || return 1

    resp=$(post '{"action": "eval", "expression": "prompt(\"Name?\")"}')
    assert_success "$resp" "dialog_prompt_dismiss: eval" || return 1
    result=$(echo "$resp" | json_get "['data']['result']")
    assert_eq "$result" "None" "dialog_prompt_dismiss: result" || return 1
    echo "OK: dialog_prompt_dismiss (result=$result)"
}

test_dialog_confirm_changes_page() {
    local resp title

    # Accept -> sets title to DELETED
    resp=$(post '{"action": "handle_dialog", "accept": true}')
    assert_success "$resp" "dialog_changes_page: handle_dialog accept" || return 1
    resp=$(post '{"action": "eval", "expression": "(() => { const r = confirm(\"Delete?\"); document.title = r ? \"DELETED\" : \"KEPT\"; return r })()"}')
    assert_success "$resp" "dialog_changes_page: eval accept" || return 1
    title=$(post '{"action": "eval", "expression": "document.title"}' | json_get "['data']['result']")
    assert_eq "$title" "DELETED" "dialog_changes_page: title after accept" || return 1

    # Dismiss -> sets title to KEPT
    resp=$(post '{"action": "handle_dialog", "accept": false}')
    assert_success "$resp" "dialog_changes_page: handle_dialog dismiss" || return 1
    resp=$(post '{"action": "eval", "expression": "(() => { const r = confirm(\"Delete?\"); document.title = r ? \"DELETED\" : \"KEPT\"; return r })()"}')
    assert_success "$resp" "dialog_changes_page: eval dismiss" || return 1
    title=$(post '{"action": "eval", "expression": "document.title"}' | json_get "['data']['result']")
    assert_eq "$title" "KEPT" "dialog_changes_page: title after dismiss" || return 1

    echo "OK: dialog_confirm_changes_page (accept=DELETED, dismiss=KEPT)"
}

ALL_TESTS+=(
    test_dialog_alert
    test_dialog_confirm_accept
    test_dialog_confirm_dismiss
    test_dialog_prompt_accept_text
    test_dialog_prompt_dismiss
    test_dialog_confirm_changes_page
)
