#!/bin/bash
# Hope Terminal - Uninstall Script
# This script removes the hope-terminal init.d service

set -e

SERVICE_NAME="hope-terminal"
INIT_SCRIPT="/etc/init.d/${SERVICE_NAME}"

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

# Check if service exists
if [ ! -f "$INIT_SCRIPT" ]; then
    echo -e "${YELLOW}Service is not installed.${NC}"
    exit 0
fi

# Stop the service if running
echo -e "${GREEN}Stopping service...${NC}"
"$INIT_SCRIPT" stop 2>/dev/null || true

# Remove runlevel symlinks
echo -e "${GREEN}Removing runlevel symlinks...${NC}"
for rl in 0 1 2 3 4 5 6; do
    rm -f "/etc/rc${rl}.d/S99${SERVICE_NAME}"
    rm -f "/etc/rc${rl}.d/K01${SERVICE_NAME}"
done

# Remove the init script
echo -e "${GREEN}Removing init script...${NC}"
rm -f "$INIT_SCRIPT"

# Remove wrapper script if exists
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAPPER_SCRIPT="${SCRIPT_DIR}/run-service.sh"
if [ -f "$WRAPPER_SCRIPT" ]; then
    echo -e "${GREEN}Removing wrapper script...${NC}"
    rm -f "$WRAPPER_SCRIPT"
fi

# Remove pidfile and logfile
rm -f /var/run/hope-terminal.pid
echo -e "${YELLOW}Note: Log file kept at /var/log/hope-terminal.log${NC}"

echo
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Uninstall Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo
echo -e "Hope Terminal service has been removed."
echo
