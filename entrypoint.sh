#!/bin/bash

PIDS=()

cleanup() {
    echo ""
    echo "[*] Shutting down..."
    for pid in "${PIDS[@]}"; do
        kill "$pid" 2>/dev/null
    done
    wait
    echo "[*] Done."
    exit 0
}

trap cleanup SIGINT SIGTERM SIGHUP EXIT

# Start Xvfb
if [ -z "$DISPLAY" ] || [ "$DISPLAY" = ":99" ]; then
    Xvfb :99 -screen 0 ${XVFB_RESOLUTION} -ac +extension GLX +render -noreset &
    PIDS+=($!)
    export DISPLAY=:99
    sleep 0.5
fi

# Start x11vnc
x11vnc -display :99 -rfbport 5901 -nopw -forever -shared -localhost &
PIDS+=($!)
sleep 0.3

# Start noVNC
websockify --web /usr/share/novnc 5900 localhost:5901 &
PIDS+=($!)
sleep 0.3

# Start session API
python main.py "$@" &
SESSION_PID=$!
PIDS+=($SESSION_PID)

# Wait for API to be ready
for i in {1..30}; do
    if curl -s http://localhost:8080/health > /dev/null 2>&1; then
        break
    fi
    sleep 0.2
done

# Banner
echo ""
echo "=============================================="
echo "  STEALTHY AUTO-BROWSE"
echo "=============================================="
echo ""
echo "  VNC:  http://localhost:5900/vnc.html"
echo "  API:  http://localhost:8080"
echo ""
echo "  Ctrl+C to exit"
echo "=============================================="
echo ""

# Wait for main.py to exit
wait $SESSION_PID
