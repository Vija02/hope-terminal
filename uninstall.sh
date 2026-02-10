#!/bin/bash
# Hope Terminal - Uninstall Script
# This script removes the hope-terminal systemd service

set -e

SERVICE_NAME="hope-terminal"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

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
if [ ! -f "$SERVICE_FILE" ]; then
    echo -e "${YELLOW}Service is not installed.${NC}"
    exit 0
fi

# Stop the service if running
echo -e "${GREEN}Stopping service...${NC}"
systemctl stop "$SERVICE_NAME" 2>/dev/null || true

# Disable the service
echo -e "${GREEN}Disabling service...${NC}"
systemctl disable "$SERVICE_NAME" 2>/dev/null || true

# Remove the service file
echo -e "${GREEN}Removing service file...${NC}"
rm -f "$SERVICE_FILE"

# Reload systemd
echo -e "${GREEN}Reloading systemd...${NC}"
systemctl daemon-reload

echo
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Uninstall Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo
echo -e "Hope Terminal service has been removed."
echo
