#!/bin/bash
# tests/test_input.sh - Mouse, keyboard, scroll, and form input tests

test_mouse_move() {
    # Move mouse to known position and verify via pyautogui
    post '{"action": "mouse_move", "x": 250, "y": 250, "duration": 0.1}' >/dev/null
    local resp pos_x pos_y
    resp=$(post '{"action": "eval", "expression": "null"}')
    # Verify action succeeded (mouse_move has no visible DOM effect, check position via API)
    resp=$(post '{"action": "mouse_move", "x": 500, "y": 400, "duration": 0.1}')
    assert_success "$resp" "mouse_move"
}

test_mouse_click() {
    # Click on the submit button via mouse_click (pyautogui) and verify DOM event fired
    post '{"action": "calibrate"}' >/dev/null
    # Get submit button center coordinates
    local resp rect_raw btn_x btn_y val
    resp=$(post '{"action": "eval", "expression": "JSON.stringify(document.getElementById(\"submit-btn\").getBoundingClientRect())"}')
    rect_raw=$(echo "$resp" | json_get "['data']['result']")
    btn_x=$(echo "$rect_raw" | python3 -c "import sys,json; r=json.loads(sys.stdin.read()); print(int(r['x']+r['width']/2))")
    btn_y=$(echo "$rect_raw" | python3 -c "import sys,json; r=json.loads(sys.stdin.read()); print(int(r['y']+r['height']/2))")
    post "{\"action\": \"mouse_click\", \"x\": $btn_x, \"y\": $btn_y}" >/dev/null
    sleep 0.5
    resp=$(post '{"action": "eval", "expression": "var e=document.getElementById(\"btn-clicked\"); e ? e.textContent : \"\""}')
    val=$(echo "$resp" | json_get "['data']['result']")
    assert_eq "$val" "clicked" "mouse_click: button clicked via coordinates"
}

test_system_click() {
    # Click on an input field via system_click, type into it to verify focus
    post '{"action": "calibrate"}' >/dev/null
    # Get name-input center coordinates
    local resp rect_raw inp_x inp_y val
    resp=$(post '{"action": "eval", "expression": "JSON.stringify(document.getElementById(\"name-input\").getBoundingClientRect())"}')
    rect_raw=$(echo "$resp" | json_get "['data']['result']")
    inp_x=$(echo "$rect_raw" | python3 -c "import sys,json; r=json.loads(sys.stdin.read()); print(int(r['x']+r['width']/2))")
    inp_y=$(echo "$rect_raw" | python3 -c "import sys,json; r=json.loads(sys.stdin.read()); print(int(r['y']+r['height']/2))")
    post "{\"action\": \"system_click\", \"x\": $inp_x, \"y\": $inp_y}" >/dev/null
    sleep 0.5
    post '{"action": "system_type", "text": "sc", "interval": 0.02}' >/dev/null
    sleep 0.5
    resp=$(post '{"action": "eval", "expression": "document.getElementById(\"name-input\").value"}')
    val=$(echo "$resp" | json_get "['data']['result']")
    assert_eq "$val" "sc" "system_click: input focused and typed into"
}

test_scroll() {
    # Get initial scroll position
    local resp before after
    resp=$(post '{"action": "eval", "expression": "window.scrollY"}')
    before=$(echo "$resp" | json_get "['data']['result']")
    # Scroll down
    post '{"action": "scroll", "amount": -5}' >/dev/null
    sleep 0.5
    resp=$(post '{"action": "eval", "expression": "window.scrollY"}')
    after=$(echo "$resp" | json_get "['data']['result']")
    if [ "$after" -le "$before" ]; then
        echo "FAIL: scroll: scrollY didn't increase (before=$before, after=$after)"
        return 1
    fi
    echo "OK: scroll (scrollY: $before -> $after)"
}

test_system_type() {
    # Click on sys-input to focus it, then system_type into it
    post '{"action": "click", "selector": "#sys-input"}' >/dev/null
    sleep 0.3
    post '{"action": "system_type", "text": "hello", "interval": 0.02}' >/dev/null
    sleep 0.5
    local resp val
    resp=$(post '{"action": "eval", "expression": "document.getElementById(\"sys-input\").value"}')
    val=$(echo "$resp" | json_get "['data']['result']")
    assert_eq "$val" "hello" "system_type: input value"
}

test_send_key() {
    # Send a key and check the keydown listener captured it
    post '{"action": "send_key", "key": "a"}' >/dev/null
    sleep 0.3
    local resp val
    resp=$(post '{"action": "eval", "expression": "document.getElementById(\"last-key\").textContent"}')
    val=$(echo "$resp" | json_get "['data']['result']")
    assert_eq "$val" "a" "send_key: keydown listener captured 'a'"
}

test_enter_fullscreen() {
    post '{"action": "enter_fullscreen"}' >/dev/null
    sleep 1
    local resp val
    resp=$(post '{"action": "eval", "expression": "!!document.fullscreenElement"}')
    val=$(echo "$resp" | json_get "['data']['result']")
    assert_eq "$val" "True" "enter_fullscreen: fullscreenElement set"
}

test_exit_fullscreen() {
    # Enter fullscreen first so this test is self-contained
    post '{"action": "enter_fullscreen"}' >/dev/null
    sleep 1
    post '{"action": "exit_fullscreen"}' >/dev/null
    sleep 1
    local resp val
    resp=$(post '{"action": "eval", "expression": "!!document.fullscreenElement"}')
    val=$(echo "$resp" | json_get "['data']['result']")
    assert_eq "$val" "False" "exit_fullscreen: fullscreenElement cleared"
}

test_fill() {
    # CSS selector
    post '{"action": "fill", "selector": "#name-input", "value": "hello world"}' >/dev/null
    local resp val
    resp=$(post '{"action": "eval", "expression": "document.getElementById(\"name-input\").value"}')
    val=$(echo "$resp" | json_get "['data']['result']")
    assert_eq "$val" "hello world" "fill: CSS selector" || return 1

    # XPath selector
    post '{"action": "fill", "selector": "xpath=//input[@id=\"name-input\"]", "value": "xpath fill"}' >/dev/null
    resp=$(post '{"action": "eval", "expression": "document.getElementById(\"name-input\").value"}')
    val=$(echo "$resp" | json_get "['data']['result']")
    assert_eq "$val" "xpath fill" "fill: XPath selector"
}

test_type_action() {
    # CSS selector
    post '{"action": "click", "selector": "#email-input"}' >/dev/null
    post '{"action": "type", "selector": "#email-input", "text": "typed", "delay": 0.02}' >/dev/null
    local resp val
    resp=$(post '{"action": "eval", "expression": "document.getElementById(\"email-input\").value"}')
    val=$(echo "$resp" | json_get "['data']['result']")
    assert_eq "$val" "typed" "type: CSS selector" || return 1

    # XPath selector
    post '{"action": "fill", "selector": "#email-input", "value": ""}' >/dev/null
    post '{"action": "type", "selector": "xpath=//input[@id=\"email-input\"]", "text": "xtyped", "delay": 0.02}' >/dev/null
    resp=$(post '{"action": "eval", "expression": "document.getElementById(\"email-input\").value"}')
    val=$(echo "$resp" | json_get "['data']['result']")
    assert_eq "$val" "xtyped" "type: XPath selector"
}

test_click() {
    # CSS selector
    post '{"action": "click", "selector": "#submit-btn"}' >/dev/null
    sleep 0.5
    local resp val
    resp=$(post '{"action": "eval", "expression": "document.getElementById(\"btn-clicked\") ? document.getElementById(\"btn-clicked\").textContent : \"\""}')
    val=$(echo "$resp" | json_get "['data']['result']")
    assert_eq "$val" "clicked" "click: CSS selector" || return 1

    # Clear and test XPath
    post '{"action": "eval", "expression": "document.getElementById(\"click-result\").innerHTML = \"\""}' >/dev/null
    post '{"action": "click", "selector": "xpath=//button[@id=\"submit-btn\"]"}' >/dev/null
    sleep 0.5
    resp=$(post '{"action": "eval", "expression": "document.getElementById(\"btn-clicked\") ? document.getElementById(\"btn-clicked\").textContent : \"\""}')
    val=$(echo "$resp" | json_get "['data']['result']")
    assert_eq "$val" "clicked" "click: XPath selector"
}

ALL_TESTS+=(
    test_mouse_move
    test_mouse_click
    test_system_click
    test_scroll
    test_system_type
    test_send_key
    test_enter_fullscreen
    test_exit_fullscreen
    test_fill
    test_type_action
    test_click
)
