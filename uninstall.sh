#!/bin/bash
# Hope Terminal - Uninstall Script
# This script removes hope-terminal autostart and sudoers config

set -e

SERVICE_NAME="hope-terminal"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Hope Terminal - Uninstall Script${NC}"
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
    ACTUAL_USER=$(stat -c '%U' "$SCRIPT_DIR")
fi

if [ "$ACTUAL_USER" = "root" ]; then
    echo -e "${YELLOW}Warning: Could not detect non-root user, using script directory owner${NC}"
fi

ACTUAL_USER_HOME=$(eval echo "~$ACTUAL_USER")

# Step 1: Stop and disable systemd user services
echo -e "${GREEN}Step 1: Stopping systemd user services...${NC}"
su - "$ACTUAL_USER" -c "systemctl --user stop hope-terminal.service" 2>/dev/null || true
su - "$ACTUAL_USER" -c "systemctl --user disable hope-terminal.service" 2>/dev/null || true
su - "$ACTUAL_USER" -c "systemctl --user stop hope-clicker.service" 2>/dev/null || true
su - "$ACTUAL_USER" -c "systemctl --user disable hope-clicker.service" 2>/dev/null || true

# Step 2: Remove systemd user services
SYSTEMD_SERVICE="${ACTUAL_USER_HOME}/.config/systemd/user/hope-terminal.service"
if [ -f "$SYSTEMD_SERVICE" ]; then
    echo -e "${GREEN}Removing hope-terminal systemd user service...${NC}"
    rm -f "$SYSTEMD_SERVICE"
fi

CLICKER_SERVICE="${ACTUAL_USER_HOME}/.config/systemd/user/hope-clicker.service"
if [ -f "$CLICKER_SERVICE" ]; then
    echo -e "${GREEN}Removing hope-clicker systemd user service...${NC}"
    rm -f "$CLICKER_SERVICE"
fi

su - "$ACTUAL_USER" -c "systemctl --user daemon-reload" 2>/dev/null || true

# Step 3: Remove autostart desktop entry
DESKTOP_FILE="${ACTUAL_USER_HOME}/.config/autostart/hope-terminal.desktop"
if [ -f "$DESKTOP_FILE" ]; then
    echo -e "${GREEN}Removing autostart entry...${NC}"
    rm -f "$DESKTOP_FILE"
fi

# Step 4: Remove launcher scripts
LAUNCHER_SCRIPT="${SCRIPT_DIR}/run-hope-terminal.sh"
if [ -f "$LAUNCHER_SCRIPT" ]; then
    echo -e "${GREEN}Removing hope-terminal launcher script...${NC}"
    rm -f "$LAUNCHER_SCRIPT"
fi

CLICKER_LAUNCHER="${SCRIPT_DIR}/run-hope-clicker.sh"
if [ -f "$CLICKER_LAUNCHER" ]; then
    echo -e "${GREEN}Removing hope-clicker launcher script...${NC}"
    rm -f "$CLICKER_LAUNCHER"
fi

# Step 5: Remove sudoers file
SUDOERS_FILE="/etc/sudoers.d/hope-terminal-shutdown"
if [ -f "$SUDOERS_FILE" ]; then
    echo -e "${GREEN}Removing sudoers configuration...${NC}"
    rm -f "$SUDOERS_FILE"
fi

# Step 6: Remove old init.d stuff if present
if [ -f "/etc/init.d/hope-terminal" ]; then
    echo -e "${GREEN}Removing old init.d script...${NC}"
    /etc/init.d/hope-terminal stop 2>/dev/null || true
    for rl in 0 1 2 3 4 5 6; do
        rm -f "/etc/rc${rl}.d/S99hope-terminal"
        rm -f "/etc/rc${rl}.d/K01hope-terminal"
    done
    rm -f "/etc/init.d/hope-terminal"
fi

# Remove old wrapper script if exists
if [ -f "${SCRIPT_DIR}/run-service.sh" ]; then
    rm -f "${SCRIPT_DIR}/run-service.sh"
fi

echo
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Uninstall Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo
echo -e "Hope Terminal and Hope Clicker have been removed."
echo -e "Note: Passwordless shutdown has been disabled."
echo -e "Note: User remains in 'input' group (may be used by other apps)."
echo
