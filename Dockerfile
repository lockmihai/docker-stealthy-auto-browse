FROM python:3.12-slim

# Prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Timezone - override with -e TZ=Your/Timezone
ENV TZ=UTC

# Install tzdata for proper timezone support
RUN apt-get update && apt-get install -y --no-install-recommends \
    tzdata \
    && rm -rf /var/lib/apt/lists/*

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

# Firefox/Camoufox dependencies - install firefox-esr to pull correct GTK deps for any arch
RUN apt-get update \
    && apt-get install -y --no-install-recommends firefox-esr fonts-liberation \
    && apt-get remove -y --purge firefox-esr \
    && rm -rf /var/lib/apt/lists/*

# UI automation tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    xdotool scrot python3-tk python3-dev \
    && rm -rf /var/lib/apt/lists/*

# Install camoufox, pyautogui, and aiohttp
RUN pip install --no-cache-dir "camoufox[geoip]" pyautogui aiohttp

# Download Camoufox browser
RUN python -m camoufox fetch

# Copy scripts and install extensions
COPY scripts/ /scripts/
RUN python /scripts/install_extensions.py

# Create directories for app and user data
RUN mkdir -p /app /userdata

# Copy app
COPY app/ /app/

# Set working directory
WORKDIR /app

# Copy entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Environment variables
ENV XVFB_RESOLUTION=1920x1080x24

# Expose ports (VNC and session HTTP)
EXPOSE 5900 8080

ENTRYPOINT ["/entrypoint.sh"]
