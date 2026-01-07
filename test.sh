#!/bin/bash

HOST="localhost"
PORT="8080"
BASE="http://${HOST}:${PORT}"

# Go to Google
curl -s -X POST "$BASE" \
    -H "Content-Type: application/json" \
    -d '{"action": "goto", "url": "https://www.google.com"}'
echo

sleep 1

# Type in search box
curl -s -X POST "$BASE" \
    -H "Content-Type: application/json" \
    -d '{"action": "type", "selector": "textarea[name=q]", "text": "what is the meaning of life"}'
echo

sleep 1

# Press Enter via eval
curl -s -X POST "$BASE" \
    -H "Content-Type: application/json" \
    -d '{"action": "eval", "expression": "document.querySelector(\"textarea[name=q]\").form.submit()"}'
echo

sleep 2

# Get the page text
curl -s -X POST "$BASE" \
    -H "Content-Type: application/json" \
    -d '{"action": "get_text"}'
echo
