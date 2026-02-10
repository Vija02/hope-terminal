#!/bin/bash
# Hope Terminal - Install Script
# This script installs hope-terminal as an init.d service

set -e

SERVICE_NAME="hope-terminal"
INIT_SCRIPT="/etc/init.d/${SERVICE_NAME}"
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

# Create the init.d script
echo -e "${GREEN}Creating init.d script...${NC}"

cat > "$INIT_SCRIPT" << INITEOF
#!/bin/bash
### BEGIN INIT INFO
# Provides:          hope-terminal
# Required-Start:    \$local_fs \$remote_fs \$syslog
# Required-Stop:     \$local_fs \$remote_fs \$syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Hope Terminal Kiosk Manager
# Description:       Manages kiosk display with power-off handling
### END INIT INFO

USER_ID="${ACTUAL_USER_ID}"
USER_NAME="${ACTUAL_USER}"
USER_HOME="${ACTUAL_USER_HOME}"
SCRIPT_DIR="${SCRIPT_DIR}"
BUN_PATH="${BUN_PATH}"
USER_COMMAND="${USER_COMMAND}"
PIDFILE="/var/run/hope-terminal.pid"
LOGFILE="/var/log/hope-terminal.log"

get_display_env() {
    # Wait for display to be available (max 60 seconds)
    for i in \$(seq 1 60); do
        # Try to find DISPLAY from the user's session
        DISPLAY_VAL=\$(su - "\$USER_NAME" -c 'echo \$DISPLAY' 2>/dev/null)
        if [ -n "\$DISPLAY_VAL" ]; then
            break
        fi
        
        # Check for X11 socket
        if [ -e "/tmp/.X11-unix/X0" ]; then
            DISPLAY_VAL=":0"
            break
        fi
        
        sleep 1
    done
    
    echo "\$DISPLAY_VAL"
}

get_xauthority() {
    # Try standard location first
    if [ -f "\${USER_HOME}/.Xauthority" ]; then
        echo "\${USER_HOME}/.Xauthority"
        return
    fi
    
    # Search in runtime dir
    XAUTH=\$(find /run/user/\${USER_ID} -name 'xauth_*' 2>/dev/null | head -1)
    if [ -n "\$XAUTH" ]; then
        echo "\$XAUTH"
        return
    fi
    
    # Search in tmp
    XAUTH=\$(find /tmp -maxdepth 1 -name 'xauth_*' -user "\$USER_NAME" 2>/dev/null | head -1)
    if [ -n "\$XAUTH" ]; then
        echo "\$XAUTH"
        return
    fi
}

start() {
    echo "Starting hope-terminal..."
    
    if [ -f "\$PIDFILE" ] && kill -0 \$(cat "\$PIDFILE") 2>/dev/null; then
        echo "hope-terminal is already running"
        return 1
    fi
    
    # Get display environment
    DISPLAY_VAL=\$(get_display_env)
    XAUTHORITY_VAL=\$(get_xauthority)
    
    if [ -z "\$DISPLAY_VAL" ]; then
        echo "Warning: Could not detect DISPLAY, using :0"
        DISPLAY_VAL=":0"
    fi
    
    echo "Using DISPLAY=\$DISPLAY_VAL"
    echo "Using XAUTHORITY=\$XAUTHORITY_VAL"
    
    # Set up environment and run
    (
        export DISPLAY="\$DISPLAY_VAL"
        export XAUTHORITY="\$XAUTHORITY_VAL"
        export XDG_RUNTIME_DIR="/run/user/\${USER_ID}"
        export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/\${USER_ID}/bus"
        export WAYLAND_DISPLAY="wayland-0"
        export HOME="\$USER_HOME"
        
        cd "\$SCRIPT_DIR"
        nohup "\$BUN_PATH" run src/index.ts -- "\$USER_COMMAND" >> "\$LOGFILE" 2>&1 &
        echo \$! > "\$PIDFILE"
    )
    
    sleep 1
    if [ -f "\$PIDFILE" ] && kill -0 \$(cat "\$PIDFILE") 2>/dev/null; then
        echo "hope-terminal started with PID \$(cat \$PIDFILE)"
    else
        echo "Failed to start hope-terminal"
        return 1
    fi
}

stop() {
    echo "Stopping hope-terminal..."
    
    if [ ! -f "\$PIDFILE" ]; then
        echo "hope-terminal is not running (no pidfile)"
        return 0
    fi
    
    PID=\$(cat "\$PIDFILE")
    
    if ! kill -0 "\$PID" 2>/dev/null; then
        echo "hope-terminal is not running (stale pidfile)"
        rm -f "\$PIDFILE"
        return 0
    fi
    
    kill "\$PID"
    
    # Wait for process to stop
    for i in \$(seq 1 10); do
        if ! kill -0 "\$PID" 2>/dev/null; then
            break
        fi
        sleep 1
    done
    
    # Force kill if still running
    if kill -0 "\$PID" 2>/dev/null; then
        echo "Force killing..."
        kill -9 "\$PID"
    fi
    
    rm -f "\$PIDFILE"
    echo "hope-terminal stopped"
}

status() {
    if [ -f "\$PIDFILE" ] && kill -0 \$(cat "\$PIDFILE") 2>/dev/null; then
        echo "hope-terminal is running with PID \$(cat \$PIDFILE)"
        return 0
    else
        echo "hope-terminal is not running"
        return 1
    fi
}

case "\$1" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        stop
        sleep 2
        start
        ;;
    status)
        status
        ;;
    *)
        echo "Usage: \$0 {start|stop|restart|status}"
        exit 1
        ;;
esac

exit 0
INITEOF

chmod 755 "$INIT_SCRIPT"
echo -e "${GREEN}Init script created at ${INIT_SCRIPT}${NC}"

# Create symbolic links for runlevels 2-5
echo -e "${GREEN}Creating runlevel symlinks...${NC}"
for rl in 2 3 4 5; do
    ln -sf "$INIT_SCRIPT" "/etc/rc${rl}.d/S99${SERVICE_NAME}"
done

# Create stop links for runlevels 0, 1, 6
for rl in 0 1 6; do
    ln -sf "$INIT_SCRIPT" "/etc/rc${rl}.d/K01${SERVICE_NAME}"
done

echo
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Installation Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo
echo -e "To start the service now:  ${YELLOW}sudo /etc/init.d/${SERVICE_NAME} start${NC}"
echo -e "To check status:           ${YELLOW}sudo /etc/init.d/${SERVICE_NAME} status${NC}"
echo -e "To view logs:              ${YELLOW}sudo tail -f /var/log/${SERVICE_NAME}.log${NC}"
echo -e "To uninstall:              ${YELLOW}sudo ./uninstall.sh${NC}"
echo
