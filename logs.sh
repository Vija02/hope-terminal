#!/bin/bash
# Hope Terminal - Log Viewer
# Shows logs from both hope-terminal and hope-clicker services

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
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
    echo "  -h, --help  Show this help message"
    echo
    echo "Examples:"
    echo "  ./logs.sh           # Show both services' logs"
    echo "  ./logs.sh terminal  # Show only hope-terminal logs"
    echo "  ./logs.sh clicker   # Show only hope-clicker logs"
}

case "${1:-all}" in
    terminal)
        echo -e "${CYAN}=== Hope Terminal Logs ===${NC}"
        journalctl --user -u hope-terminal -f
        ;;
    clicker)
        echo -e "${CYAN}=== Hope Clicker Logs ===${NC}"
        journalctl --user -u hope-clicker -f
        ;;
    all)
        echo -e "${CYAN}=== Hope Terminal & Clicker Logs ===${NC}"
        journalctl --user -u hope-terminal -u hope-clicker -f
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
