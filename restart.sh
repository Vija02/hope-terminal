#!/bin/bash
# Hope Terminal - Restart Script
# Restarts the hope-terminal and hope-clicker services

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Hope Terminal - Restart${NC}"
echo -e "${GREEN}========================================${NC}"
echo

echo -e "${YELLOW}Restarting hope-terminal...${NC}"
systemctl --user restart hope-terminal.service || echo -e "${RED}Failed to restart hope-terminal${NC}"

echo -e "${YELLOW}Restarting hope-clicker...${NC}"
systemctl --user restart hope-clicker.service || echo -e "${RED}Failed to restart hope-clicker${NC}"

echo
echo -e "${GREEN}Done!${NC}"
echo
echo -e "Status:"
systemctl --user status hope-terminal.service --no-pager || true
echo
systemctl --user status hope-clicker.service --no-pager || true
