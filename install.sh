#!/bin/bash
# Hope Terminal - Install Script
# This script installs hope-terminal as a user autostart with passwordless shutdown

set -e

SERVICE_NAME="hope-terminal"
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

ACTUAL_USER_HOME=$(eval echo "~$ACTUAL_USER")

echo -e "${YELLOW}Detected user:${NC} $ACTUAL_USER"
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

# Step 1: Configure passwordless shutdown
echo -e "${GREEN}Step 1: Configuring passwordless shutdown...${NC}"

SUDOERS_FILE="/etc/sudoers.d/hope-terminal-shutdown"
cat > "$SUDOERS_FILE" << EOF
# Allow $ACTUAL_USER to shutdown without password (for hope-terminal)
$ACTUAL_USER ALL=(ALL) NOPASSWD: /sbin/shutdown
$ACTUAL_USER ALL=(ALL) NOPASSWD: /sbin/poweroff
$ACTUAL_USER ALL=(ALL) NOPASSWD: /sbin/reboot
EOF

chmod 440 "$SUDOERS_FILE"
echo -e "${GREEN}Created sudoers file at ${SUDOERS_FILE}${NC}"

# Step 2: Create the launcher script
echo -e "${GREEN}Step 2: Creating launcher script...${NC}"

LAUNCHER_SCRIPT="${SCRIPT_DIR}/run-hope-terminal.sh"
cat > "$LAUNCHER_SCRIPT" << EOF
#!/bin/bash
# Hope Terminal Launcher Script

cd "${SCRIPT_DIR}"
exec "${BUN_PATH}" run src/index.ts -- "${USER_COMMAND}"
EOF

chmod +x "$LAUNCHER_SCRIPT"
chown "$ACTUAL_USER:$ACTUAL_USER" "$LAUNCHER_SCRIPT"
echo -e "${GREEN}Created launcher at ${LAUNCHER_SCRIPT}${NC}"

# Step 3: Create autostart desktop entry
echo -e "${GREEN}Step 3: Creating autostart entry...${NC}"

AUTOSTART_DIR="${ACTUAL_USER_HOME}/.config/autostart"
mkdir -p "$AUTOSTART_DIR"
chown "$ACTUAL_USER:$ACTUAL_USER" "$AUTOSTART_DIR"

DESKTOP_FILE="${AUTOSTART_DIR}/hope-terminal.desktop"
cat > "$DESKTOP_FILE" << EOF
[Desktop Entry]
Type=Application
Name=Hope Terminal
Comment=Kiosk Display Manager with Power-Off Handling
Exec=${LAUNCHER_SCRIPT}
Terminal=false
Hidden=false
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=5
EOF

chown "$ACTUAL_USER:$ACTUAL_USER" "$DESKTOP_FILE"
echo -e "${GREEN}Created autostart entry at ${DESKTOP_FILE}${NC}"

# Step 4: Create systemd user service (alternative method)
echo -e "${GREEN}Step 4: Creating systemd user service (alternative)...${NC}"

SYSTEMD_USER_DIR="${ACTUAL_USER_HOME}/.config/systemd/user"
mkdir -p "$SYSTEMD_USER_DIR"
chown -R "$ACTUAL_USER:$ACTUAL_USER" "${ACTUAL_USER_HOME}/.config/systemd"

SYSTEMD_SERVICE="${SYSTEMD_USER_DIR}/hope-terminal.service"
cat > "$SYSTEMD_SERVICE" << EOF
[Unit]
Description=Hope Terminal Kiosk Manager
After=graphical-session.target

[Service]
Type=simple
WorkingDirectory=${SCRIPT_DIR}
ExecStart=${LAUNCHER_SCRIPT}
Restart=on-failure
RestartSec=10

[Install]
WantedBy=graphical-session.target
EOF

chown "$ACTUAL_USER:$ACTUAL_USER" "$SYSTEMD_SERVICE"
echo -e "${GREEN}Created systemd user service at ${SYSTEMD_SERVICE}${NC}"

# Enable the systemd user service
echo -e "${GREEN}Enabling systemd user service...${NC}"
su - "$ACTUAL_USER" -c "systemctl --user daemon-reload" || true
su - "$ACTUAL_USER" -c "systemctl --user enable hope-terminal.service" || true

echo
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Installation Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo
echo -e "The service will start automatically on login."
echo
echo -e "To start now (choose one):"
echo -e "  ${YELLOW}${LAUNCHER_SCRIPT}${NC}"
echo -e "  ${YELLOW}systemctl --user start hope-terminal${NC}"
echo
echo -e "To check status:"
echo -e "  ${YELLOW}systemctl --user status hope-terminal${NC}"
echo
echo -e "To view logs:"
echo -e "  ${YELLOW}journalctl --user -u hope-terminal -f${NC}"
echo
echo -e "To uninstall:"
echo -e "  ${YELLOW}sudo ./uninstall.sh${NC}"
echo
