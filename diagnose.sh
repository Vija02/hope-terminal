#!/bin/bash
# Hope Terminal - Diagnostic Script
# Checks system setup and identifies issues

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  Hope Terminal - Diagnostic Report${NC}"
echo -e "${CYAN}========================================${NC}"
echo

# System info
echo -e "${GREEN}1. System Info${NC}"
echo "   OS: $(lsb_release -d 2>/dev/null | cut -f2 || cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
echo "   Kernel: $(uname -r)"
echo "   User: $USER"
echo

# Check dependencies
echo -e "${GREEN}2. Dependencies${NC}"

check_cmd() {
    if command -v "$1" &> /dev/null; then
        echo -e "   $1: ${GREEN}installed${NC} ($(which $1))"
        return 0
    else
        echo -e "   $1: ${RED}NOT FOUND${NC}"
        return 1
    fi
}

check_cmd bun
check_cmd xdotool
check_cmd wmctrl
check_cmd firefox || check_cmd firefox-esr
echo

# Check input group
echo -e "${GREEN}3. Input Group Access${NC}"
if groups | grep -q '\binput\b'; then
    echo -e "   User in 'input' group: ${GREEN}YES${NC}"
else
    echo -e "   User in 'input' group: ${RED}NO${NC}"
    echo -e "   ${YELLOW}Run: sudo usermod -aG input \$USER && logout${NC}"
fi

# Check /dev/input access
if [ -r /dev/input/event0 ]; then
    echo -e "   Can read /dev/input: ${GREEN}YES${NC}"
else
    echo -e "   Can read /dev/input: ${RED}NO${NC}"
fi
echo

# Check for clicker device
echo -e "${GREEN}4. Presentation Clicker Device${NC}"
if [ -f /proc/bus/input/devices ]; then
    clicker=$(grep -A5 "USB RF PRESENT" /proc/bus/input/devices 2>/dev/null | head -10)
    if [ -n "$clicker" ]; then
        echo -e "   USB RF PRESENT: ${GREEN}FOUND${NC}"
        echo "$clicker" | sed 's/^/   /'
    else
        echo -e "   USB RF PRESENT: ${YELLOW}NOT FOUND${NC}"
        echo "   Available keyboard devices:"
        grep -B1 "kbd" /proc/bus/input/devices | grep "Name" | sed 's/^/   /'
    fi
else
    echo -e "   ${RED}Cannot read /proc/bus/input/devices${NC}"
fi
echo

# Check systemd services
echo -e "${GREEN}5. Systemd User Services${NC}"

check_service() {
    local svc="$1"
    local file="$HOME/.config/systemd/user/${svc}.service"
    
    if [ -f "$file" ]; then
        echo -e "   $svc.service: ${GREEN}installed${NC}"
        local status=$(systemctl --user is-active "$svc" 2>/dev/null)
        local enabled=$(systemctl --user is-enabled "$svc" 2>/dev/null)
        echo "     Status: $status, Enabled: $enabled"
    else
        echo -e "   $svc.service: ${YELLOW}not installed${NC}"
    fi
}

check_service hope-terminal
check_service hope-clicker
echo

# Check autostart
echo -e "${GREEN}6. Desktop Autostart${NC}"
if [ -f "$HOME/.config/autostart/hope-terminal.desktop" ]; then
    echo -e "   hope-terminal.desktop: ${GREEN}installed${NC}"
else
    echo -e "   hope-terminal.desktop: ${YELLOW}not installed${NC}"
fi
echo

# Check running processes
echo -e "${GREEN}7. Running Processes${NC}"

terminal_pid=$(pgrep -f "bun.*index.ts" 2>/dev/null)
if [ -n "$terminal_pid" ]; then
    echo -e "   hope-terminal: ${GREEN}running${NC} (PID: $terminal_pid)"
else
    echo -e "   hope-terminal: ${YELLOW}not running${NC}"
fi

clicker_pid=$(pgrep -f "bun.*clicker-remap.ts" 2>/dev/null)
if [ -n "$clicker_pid" ]; then
    echo -e "   hope-clicker: ${GREEN}running${NC} (PID: $clicker_pid)"
else
    echo -e "   hope-clicker: ${YELLOW}not running${NC}"
fi

firefox_pid=$(pgrep -f "firefox" 2>/dev/null | head -1)
if [ -n "$firefox_pid" ]; then
    echo -e "   firefox: ${GREEN}running${NC} (PID: $firefox_pid)"
else
    echo -e "   firefox: ${YELLOW}not running${NC}"
fi
echo

# Check Firefox window
echo -e "${GREEN}8. Firefox Window (via wmctrl)${NC}"
if command -v wmctrl &> /dev/null; then
    firefox_window=$(wmctrl -l 2>/dev/null | grep -iE "(firefox|mozilla)" | head -1)
    if [ -n "$firefox_window" ]; then
        echo -e "   ${GREEN}Found:${NC} $firefox_window"
    else
        echo -e "   ${YELLOW}No Firefox window found${NC}"
    fi
else
    echo -e "   ${RED}wmctrl not installed${NC}"
fi
echo

# Test clicker script
echo -e "${GREEN}9. Clicker Script Test${NC}"
echo "   Testing: bun run src/clicker-remap.ts --list"
cd "$SCRIPT_DIR"
timeout 5 bun run src/clicker-remap.ts --list 2>&1 | head -20 | sed 's/^/   /'
echo

# Summary
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  Summary${NC}"
echo -e "${CYAN}========================================${NC}"
echo
echo "To start services manually:"
echo -e "  ${YELLOW}systemctl --user start hope-terminal${NC}"
echo -e "  ${YELLOW}systemctl --user start hope-clicker${NC}"
echo
echo "To install/reinstall:"
echo -e "  ${YELLOW}sudo ./install.sh${NC}"
echo
echo "To test clicker manually:"
echo -e "  ${YELLOW}bun run clicker${NC}"
echo
