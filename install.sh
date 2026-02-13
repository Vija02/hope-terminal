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

# Default command - pi-streamer
PI_STREAMER_PATH="${SCRIPT_DIR}/../pi-streamer/src/index.ts"
DEFAULT_COMMAND="STREAM_URL=https://recordings.michaelsalim.co.uk/stream ${BUN_PATH} run ${PI_STREAMER_PATH}"

# Ask for the command to run
echo -e "Default command: ${YELLOW}${DEFAULT_COMMAND}${NC}"
read -p "Enter the command to run (press Enter for default): " USER_COMMAND
USER_COMMAND="${USER_COMMAND:-$DEFAULT_COMMAND}"

echo
echo -e "${YELLOW}Command:${NC} $USER_COMMAND"
echo

# Step 1: Install required dependencies
echo -e "${GREEN}Step 1: Checking required dependencies...${NC}"

MISSING_DEPS=""
if ! command -v xdotool &> /dev/null; then
    MISSING_DEPS="$MISSING_DEPS xdotool"
fi
if ! command -v wmctrl &> /dev/null; then
    MISSING_DEPS="$MISSING_DEPS wmctrl"
fi

if [ -n "$MISSING_DEPS" ]; then
    echo -e "${YELLOW}Installing missing dependencies:${NC}$MISSING_DEPS"
    apt-get update
    apt-get install -y $MISSING_DEPS
    echo -e "${GREEN}Installed$MISSING_DEPS${NC}"
else
    echo -e "${GREEN}All dependencies already installed (xdotool, wmctrl)${NC}"
fi

# Add user to input group for clicker access
if ! groups "$ACTUAL_USER" | grep -q '\binput\b'; then
    usermod -aG input "$ACTUAL_USER"
    echo -e "${GREEN}Added $ACTUAL_USER to input group (logout required for this to take effect)${NC}"
else
    echo -e "${YELLOW}User $ACTUAL_USER is already in input group${NC}"
fi

# Step 2: Configure passwordless shutdown
echo -e "${GREEN}Step 2: Configuring passwordless shutdown...${NC}"

SUDOERS_FILE="/etc/sudoers.d/hope-terminal-shutdown"
cat > "$SUDOERS_FILE" << EOF
# Allow $ACTUAL_USER to shutdown without password (for hope-terminal)
$ACTUAL_USER ALL=(ALL) NOPASSWD: /sbin/shutdown
$ACTUAL_USER ALL=(ALL) NOPASSWD: /sbin/poweroff
$ACTUAL_USER ALL=(ALL) NOPASSWD: /sbin/reboot
EOF

chmod 440 "$SUDOERS_FILE"
echo -e "${GREEN}Created sudoers file at ${SUDOERS_FILE}${NC}"

# Step 3: Create the launcher script
echo -e "${GREEN}Step 3: Creating launcher script...${NC}"

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

# Step 4: Create autostart desktop entry
echo -e "${GREEN}Step 4: Creating autostart entry...${NC}"

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

# Step 5: Create systemd user service (alternative method)
echo -e "${GREEN}Step 5: Creating systemd user services...${NC}"

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

# Create clicker launcher script
CLICKER_LAUNCHER="${SCRIPT_DIR}/run-hope-clicker.sh"
cat > "$CLICKER_LAUNCHER" << EOF
#!/bin/bash
# Hope Clicker Launcher Script

cd "${SCRIPT_DIR}"
exec "${BUN_PATH}" run src/clicker-remap.ts
EOF

chmod +x "$CLICKER_LAUNCHER"
chown "$ACTUAL_USER:$ACTUAL_USER" "$CLICKER_LAUNCHER"
echo -e "${GREEN}Created clicker launcher at ${CLICKER_LAUNCHER}${NC}"

# Create clicker systemd user service
CLICKER_SERVICE="${SYSTEMD_USER_DIR}/hope-clicker.service"
cat > "$CLICKER_SERVICE" << EOF
[Unit]
Description=Hope Clicker - Presentation Clicker Key Forwarder
After=graphical-session.target

[Service]
Type=simple
WorkingDirectory=${SCRIPT_DIR}
ExecStart=${CLICKER_LAUNCHER}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=graphical-session.target
EOF

chown "$ACTUAL_USER:$ACTUAL_USER" "$CLICKER_SERVICE"
echo -e "${GREEN}Created clicker service at ${CLICKER_SERVICE}${NC}"

# Enable the systemd user services
echo -e "${GREEN}Enabling systemd user services...${NC}"

# Get the user's UID for the XDG_RUNTIME_DIR
ACTUAL_USER_UID=$(id -u "$ACTUAL_USER")

# systemctl --user requires access to the user's D-Bus session
# We need to set XDG_RUNTIME_DIR and DBUS_SESSION_BUS_ADDRESS
if [ -S "/run/user/${ACTUAL_USER_UID}/bus" ]; then
    su - "$ACTUAL_USER" -c "XDG_RUNTIME_DIR=/run/user/${ACTUAL_USER_UID} systemctl --user daemon-reload" || true
    su - "$ACTUAL_USER" -c "XDG_RUNTIME_DIR=/run/user/${ACTUAL_USER_UID} systemctl --user enable hope-terminal.service" || true
    su - "$ACTUAL_USER" -c "XDG_RUNTIME_DIR=/run/user/${ACTUAL_USER_UID} systemctl --user enable hope-clicker.service" || true
else
    echo -e "${YELLOW}User session not running. Services will be enabled on next login.${NC}"
    echo -e "${YELLOW}Run these commands after logging in as $ACTUAL_USER:${NC}"
    echo -e "  systemctl --user daemon-reload"
    echo -e "  systemctl --user enable hope-terminal.service"
    echo -e "  systemctl --user enable hope-clicker.service"
fi

echo
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Installation Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo
echo -e "${YELLOW}NOTE: You may need to logout and login again for the input group to take effect.${NC}"
echo
echo -e "The services will start automatically on login."
echo
echo -e "To start now:"
echo -e "  ${YELLOW}systemctl --user start hope-terminal${NC}"
echo -e "  ${YELLOW}systemctl --user start hope-clicker${NC}"
echo
echo -e "To check status:"
echo -e "  ${YELLOW}systemctl --user status hope-terminal${NC}"
echo -e "  ${YELLOW}systemctl --user status hope-clicker${NC}"
echo
echo -e "To view logs:"
echo -e "  ${YELLOW}journalctl --user -u hope-terminal -f${NC}"
echo -e "  ${YELLOW}journalctl --user -u hope-clicker -f${NC}"
echo
echo -e "To uninstall:"
echo -e "  ${YELLOW}sudo ./uninstall.sh${NC}"
echo
