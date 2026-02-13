#!/bin/bash
# Hope Terminal - Log Viewer
# Shows logs from both hope-terminal and hope-clicker services

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m' # No Color

show_help() {
    echo -e "${GREEN}Hope Terminal - Log Viewer${NC}"
    echo
    echo "Usage: ./logs.sh [option]"
    echo
    echo "Options:"
    echo "  terminal    Show hope-terminal logs only"
    echo "  clicker     Show hope-clicker logs only"
    echo "  all         Show both logs (default)"
    echo "  status      Show service status"
    echo "  -h, --help  Show this help message"
    echo
    echo "Examples:"
    echo "  ./logs.sh           # Show both services' logs"
    echo "  ./logs.sh terminal  # Show only hope-terminal logs"
    echo "  ./logs.sh clicker   # Show only hope-clicker logs"
    echo "  ./logs.sh status    # Check if services are running"
}

show_status() {
    echo -e "${CYAN}=== Service Status ===${NC}"
    echo
    echo -e "${GREEN}hope-terminal:${NC}"
    systemctl --user status hope-terminal --no-pager 2>/dev/null || echo -e "${YELLOW}  Service not installed or not running${NC}"
    echo
    echo -e "${GREEN}hope-clicker:${NC}"
    systemctl --user status hope-clicker --no-pager 2>/dev/null || echo -e "${YELLOW}  Service not installed or not running${NC}"
}

show_logs() {
    local services="$1"
    local title="$2"
    
    echo -e "${CYAN}=== $title ===${NC}"
    echo
    
    # First show recent logs (last 50 lines), then follow
    echo -e "${YELLOW}Recent logs:${NC}"
    journalctl --user $services --no-pager -n 50 2>/dev/null
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}No logs found. Services may not be running.${NC}"
        echo
        echo -e "To start the services:"
        echo -e "  ${YELLOW}systemctl --user start hope-terminal${NC}"
        echo -e "  ${YELLOW}systemctl --user start hope-clicker${NC}"
        echo
        echo -e "Or check status with:"
        echo -e "  ${YELLOW}./logs.sh status${NC}"
        exit 1
    fi
    
    echo
    echo -e "${YELLOW}Following new logs (Ctrl+C to stop)...${NC}"
    echo
    journalctl --user $services -f
}

case "${1:-all}" in
    terminal)
        show_logs "-u hope-terminal" "Hope Terminal Logs"
        ;;
    clicker)
        show_logs "-u hope-clicker" "Hope Clicker Logs"
        ;;
    all)
        show_logs "-u hope-terminal -u hope-clicker" "Hope Terminal & Clicker Logs"
        ;;
    status)
        show_status
        ;;
    -h|--help)
        show_help
        ;;
    *)
        echo -e "${YELLOW}Unknown option: $1${NC}"
        echo
        show_help
        exit 1
        ;;
esac
