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
    
    # Check systemd services
    echo -e "${GREEN}Systemd Services:${NC}"
    echo -e "  hope-terminal: $(systemctl --user is-active hope-terminal 2>/dev/null || echo 'not installed')"
    echo -e "  hope-clicker:  $(systemctl --user is-active hope-clicker 2>/dev/null || echo 'not installed')"
    echo
    
    # Check running processes
    echo -e "${GREEN}Running Processes:${NC}"
    
    local terminal_pid=$(pgrep -f "bun.*index.ts" 2>/dev/null)
    if [ -n "$terminal_pid" ]; then
        echo -e "  hope-terminal: ${GREEN}running${NC} (PID: $terminal_pid)"
    else
        echo -e "  hope-terminal: ${YELLOW}not running${NC}"
    fi
    
    local clicker_pid=$(pgrep -f "bun.*clicker-remap.ts" 2>/dev/null)
    if [ -n "$clicker_pid" ]; then
        echo -e "  hope-clicker:  ${GREEN}running${NC} (PID: $clicker_pid)"
    else
        echo -e "  hope-clicker:  ${YELLOW}not running${NC}"
    fi
    
    # Check Firefox
    echo
    echo -e "${GREEN}Firefox:${NC}"
    local firefox_pid=$(pgrep -f "firefox" 2>/dev/null | head -1)
    if [ -n "$firefox_pid" ]; then
        echo -e "  ${GREEN}running${NC} (PID: $firefox_pid)"
    else
        echo -e "  ${YELLOW}not running${NC}"
    fi
}

show_logs() {
    local services="$1"
    local title="$2"
    
    echo -e "${CYAN}=== $title ===${NC}"
    echo
    
    # Try journalctl first (for systemd services)
    local has_logs=false
    
    # Check if journalctl has any logs for these services (from this boot only)
    local log_count=$(journalctl --user $services --no-pager -b -n 1 2>/dev/null | wc -l)
    
    if [ "$log_count" -gt 0 ]; then
        has_logs=true
        echo -e "${YELLOW}Logs from this boot:${NC}"
        journalctl --user $services --no-pager -b -n 100 2>/dev/null
        echo
        echo -e "${YELLOW}Following new logs (Ctrl+C to stop)...${NC}"
        echo
        journalctl --user $services -f
    fi
    
    if [ "$has_logs" = false ]; then
        echo -e "${YELLOW}No systemd logs found.${NC}"
        echo
        echo -e "The service might be running via:"
        echo -e "  - Desktop autostart (logs go to ~/.xsession-errors)"
        echo -e "  - Direct terminal execution (logs shown in that terminal)"
        echo
        
        # Check .xsession-errors
        if [ -f ~/.xsession-errors ]; then
            echo -e "${YELLOW}Recent entries from ~/.xsession-errors:${NC}"
            grep -E "(hope|Hope|firefox|Firefox|clicker|Clicker)" ~/.xsession-errors 2>/dev/null | tail -50
            echo
        fi
        
        # Show status instead
        echo -e "${YELLOW}Current status:${NC}"
        show_status
        
        echo
        echo -e "To enable systemd logging, start services with:"
        echo -e "  ${YELLOW}systemctl --user start hope-terminal${NC}"
        echo -e "  ${YELLOW}systemctl --user start hope-clicker${NC}"
    fi
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
