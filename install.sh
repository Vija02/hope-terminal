#!/bin/bash
# Hope Terminal - Install Script
# This script installs hope-terminal as a systemd service running as root

set -e

SERVICE_NAME="hope-terminal"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Hope Terminal - Installation Script${NC}"
echo -e "${GREEN}========================================${NC}"
echo

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root (use sudo)${NC}"
    exit 1
fi

# Detect the actual user (not root)
if [ -n "$SUDO_USER" ]; then
    ACTUAL_USER="$SUDO_USER"
else
    # Fallback: find the user who owns the current directory
    ACTUAL_USER=$(stat -c '%U' "$SCRIPT_DIR")
fi

if [ "$ACTUAL_USER" = "root" ]; then
    echo -e "${RED}Error: Could not detect non-root user${NC}"
    echo "Please run this script with: sudo ./install.sh"
    exit 1
fi

ACTUAL_USER_ID=$(id -u "$ACTUAL_USER")
ACTUAL_USER_HOME=$(eval echo "~$ACTUAL_USER")

echo -e "${YELLOW}Detected user:${NC} $ACTUAL_USER (UID: $ACTUAL_USER_ID)"
echo -e "${YELLOW}User home:${NC} $ACTUAL_USER_HOME"
echo -e "${YELLOW}Script directory:${NC} $SCRIPT_DIR"
echo

# Check if bun is installed
BUN_PATH=$(which bun 2>/dev/null || echo "")
if [ -z "$BUN_PATH" ]; then
    # Try common locations
    if [ -x "/usr/bin/bun" ]; then
        BUN_PATH="/usr/bin/bun"
    elif [ -x "/usr/local/bin/bun" ]; then
        BUN_PATH="/usr/local/bin/bun"
    elif [ -x "$ACTUAL_USER_HOME/.bun/bin/bun" ]; then
        BUN_PATH="$ACTUAL_USER_HOME/.bun/bin/bun"
    else
        echo -e "${RED}Error: bun not found. Please install bun first.${NC}"
        exit 1
    fi
fi

echo -e "${YELLOW}Bun path:${NC} $BUN_PATH"
echo

# Ask for the command to run
read -p "Enter the command to run (default: echo 'Hope Terminal Started'): " USER_COMMAND
USER_COMMAND="${USER_COMMAND:-echo 'Hope Terminal Started'}"

echo
echo -e "${YELLOW}Command:${NC} $USER_COMMAND"
echo

# Create the systemd service file
echo -e "${GREEN}Creating systemd service...${NC}"

cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Hope Terminal Kiosk Manager
After=graphical-session.target
Wants=graphical-session.target

[Service]
Type=simple
User=root

# Wait for graphical session to be ready
ExecStartPre=/bin/bash -c 'until [ -n "\$(ls /run/user/${ACTUAL_USER_ID}/wayland-* 2>/dev/null || echo \$DISPLAY)" ]; do sleep 1; done; sleep 3'

# Environment for display access
Environment=DISPLAY=:0
Environment=WAYLAND_DISPLAY=wayland-0
Environment=XDG_RUNTIME_DIR=/run/user/${ACTUAL_USER_ID}
Environment=DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/${ACTUAL_USER_ID}/bus

# Working directory
WorkingDirectory=${SCRIPT_DIR}

# The command to run
ExecStart=${BUN_PATH} run src/index.ts -- "${USER_COMMAND}"

# Restart on failure
Restart=on-failure
RestartSec=10

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${SERVICE_NAME}

[Install]
WantedBy=graphical.target
EOF

echo -e "${GREEN}Service file created at ${SERVICE_FILE}${NC}"

# Reload systemd
echo -e "${GREEN}Reloading systemd...${NC}"
systemctl daemon-reload

# Enable the service
echo -e "${GREEN}Enabling service...${NC}"
systemctl enable "$SERVICE_NAME"

echo
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Installation Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo
echo -e "To start the service now:  ${YELLOW}sudo systemctl start ${SERVICE_NAME}${NC}"
echo -e "To check status:           ${YELLOW}sudo systemctl status ${SERVICE_NAME}${NC}"
echo -e "To view logs:              ${YELLOW}sudo journalctl -u ${SERVICE_NAME} -f${NC}"
echo -e "To uninstall:              ${YELLOW}sudo ./uninstall.sh${NC}"
echo
