#!/bin/bash
# tests/test_dialogs.sh - Dialog handling tests (alert, confirm, prompt)

# --- Table-driven dialog tests ---

_dialog_case() {
    local label="$1" handle_json="$2" eval_expr="$3"
    local expected_result="$4" expected_type="$5" expected_msg="$6"

    local resp

    # Pre-configure dialog handler if specified
    if [ -n "$handle_json" ]; then
        resp=$(post "$handle_json")
        assert_success "$resp" "dialog[$label]: handle_dialog" || return 1
    fi

    # Trigger dialog — use python to build JSON safely (avoids shell quoting issues)
    resp=$(python3 -c "
import json,sys,urllib.request
body = json.dumps({'action':'eval','expression':sys.argv[1]}).encode()
req = urllib.request.Request(sys.argv[2], data=body, headers={'Content-Type':'application/json'})
print(urllib.request.urlopen(req, timeout=30).read().decode())
" "$eval_expr" "$BASE")
    assert_success "$resp" "dialog[$label]: eval" || return 1

    # Check result if expected
    if [ -n "$expected_result" ]; then
        local result
        result=$(echo "$resp" | json_get "['data']['result']")
        assert_eq "$result" "$expected_result" "dialog[$label]: result" || return 1
    fi

    # Check captured dialog info
    resp=$(post '{"action": "get_last_dialog"}')
    assert_success "$resp" "dialog[$label]: get_last_dialog" || return 1

    local dtype msg
    dtype=$(echo "$resp" | json_get "['data']['dialog']['type']")
    msg=$(echo "$resp" | json_get "['data']['dialog']['message']")
    assert_eq "$dtype" "$expected_type" "dialog[$label]: type" || return 1
    assert_eq "$msg" "$expected_msg" "dialog[$label]: message" || return 1

    echo "  - $label: OK (type=$dtype, message=$msg)"
}

test_dialogs() {
    _dialog_case "alert" "" 'alert(1234)' "" "alert" "1234" || return 1
    _dialog_case "confirm_accept" "" 'confirm("Accept me")' "True" "confirm" "Accept me" || return 1
    _dialog_case "confirm_dismiss" '{"action":"handle_dialog","accept":false}' 'confirm("Dismiss me")' "False" "confirm" "Dismiss me" || return 1
    _dialog_case "prompt_accept" '{"action":"handle_dialog","accept":true,"text":"hello"}' 'prompt("Name?","default")' "hello" "prompt" "Name?" || return 1
    _dialog_case "prompt_dismiss" '{"action":"handle_dialog","accept":false}' 'prompt("Name?")' "None" "prompt" "Name?" || return 1
    echo "OK: dialogs (5 cases passed)"
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
    test_dialogs
    test_dialog_confirm_changes_page
)
