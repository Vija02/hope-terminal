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

# Create a wrapper script that sets up the environment
WRAPPER_SCRIPT="${SCRIPT_DIR}/run-service.sh"

cat > "$WRAPPER_SCRIPT" << 'WRAPPER_EOF'
#!/bin/bash
# This script sets up the environment for hope-terminal when running as a service

USER_ID="__USER_ID__"
USER_HOME="__USER_HOME__"
SCRIPT_DIR="__SCRIPT_DIR__"
BUN_PATH="__BUN_PATH__"
USER_COMMAND="__USER_COMMAND__"

# Wait for display to be available
for i in {1..60}; do
    # Check for Wayland
    if [ -e "/run/user/${USER_ID}/wayland-0" ]; then
        export WAYLAND_DISPLAY=wayland-0
        break
    fi
    # Check for X11
    if [ -e "/tmp/.X11-unix/X0" ]; then
        export DISPLAY=:0
        break
    fi
    sleep 1
done

# Set up environment
export XDG_RUNTIME_DIR="/run/user/${USER_ID}"
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${USER_ID}/bus"
export DISPLAY=:0
export WAYLAND_DISPLAY=wayland-0

# Find XAUTHORITY - needed for xrandr to work
if [ -f "${USER_HOME}/.Xauthority" ]; then
    export XAUTHORITY="${USER_HOME}/.Xauthority"
else
    # Try to find it in /run/user
    XAUTH_FILE=$(find /run/user/${USER_ID} -name 'xauth_*' -o -name '.Xauthority' 2>/dev/null | head -1)
    if [ -n "$XAUTH_FILE" ]; then
        export XAUTHORITY="$XAUTH_FILE"
    fi
fi

# Give the graphical session a moment to fully initialize
sleep 3

cd "$SCRIPT_DIR"
exec "$BUN_PATH" run src/index.ts -- "$USER_COMMAND"
WRAPPER_EOF

# Replace placeholders in wrapper script
sed -i "s|__USER_ID__|${ACTUAL_USER_ID}|g" "$WRAPPER_SCRIPT"
sed -i "s|__USER_HOME__|${ACTUAL_USER_HOME}|g" "$WRAPPER_SCRIPT"
sed -i "s|__SCRIPT_DIR__|${SCRIPT_DIR}|g" "$WRAPPER_SCRIPT"
sed -i "s|__BUN_PATH__|${BUN_PATH}|g" "$WRAPPER_SCRIPT"
sed -i "s|__USER_COMMAND__|${USER_COMMAND}|g" "$WRAPPER_SCRIPT"

chmod +x "$WRAPPER_SCRIPT"
echo -e "${GREEN}Created wrapper script at ${WRAPPER_SCRIPT}${NC}"

cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Hope Terminal Kiosk Manager
After=graphical.target
Wants=graphical.target

[Service]
Type=simple
User=root

# Working directory
WorkingDirectory=${SCRIPT_DIR}

# The command to run (via wrapper script that sets up environment)
ExecStart=${WRAPPER_SCRIPT}

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
