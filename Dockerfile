FROM python:3.12-slim

# Prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Base utils
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget curl gnupg ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# X11 and display
RUN apt-get update && apt-get install -y --no-install-recommends \
    xvfb xauth dbus dbus-x11 \
    && rm -rf /var/lib/apt/lists/*

# VNC
RUN apt-get update && apt-get install -y --no-install-recommends \
    x11vnc novnc websockify \
    && rm -rf /var/lib/apt/lists/*

# Browser dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    fonts-liberation \
    libasound2 \
    libatk-bridge2.0-0 \
    libatk1.0-0 \
    libatspi2.0-0 \
    libcups2 \
    libdbus-1-3 \
    libdrm2 \
    libgbm1 \
    libgtk-3-0 \
    libnspr4 \
    libnss3 \
    libwayland-client0 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libxkbcommon0 \
    libxrandr2 \
    libxcb-xinerama0 \
    && rm -rf /var/lib/apt/lists/*

# UI automation tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    xdotool scrot python3-tk python3-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Brave browser
RUN curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg \
    https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] \
    https://brave-browser-apt-release.s3.brave.com/ stable main" \
    > /etc/apt/sources.list.d/brave-browser-release.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends brave-browser \
    && rm -rf /var/lib/apt/lists/*

# Install patchright, pyautogui, and aiohttp
RUN pip install --no-cache-dir patchright pyautogui aiohttp

# Create directories for app and user data
RUN mkdir -p /app /userdata

# Copy app
COPY app/ /app/

# Set working directory
WORKDIR /app

# Create entrypoint script
RUN cat > /entrypoint.sh << 'EOF'
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
EOF

RUN chmod +x /entrypoint.sh

# Environment variables
ENV XVFB_RESOLUTION=1920x1080x24

# Expose ports (VNC and session HTTP)
EXPOSE 5900 8080

ENTRYPOINT ["/entrypoint.sh"]
