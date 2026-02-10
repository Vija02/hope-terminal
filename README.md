# Hope Terminal

A kiosk display manager that monitors for secondary screens, launches a browser in fullscreen mode, and handles power-off gracefully.

## Features

- Detects secondary screens (via xrandr) and launches Firefox in kiosk mode
- Continuously monitors for screen connect/disconnect
- Auto-restarts the browser if closed (e.g., Alt+F4)
- Runs a user-specified command with auto-restart on exit
- Monitors AC power and triggers graceful shutdown when power is disconnected
- Works on both X11 and Wayland (via XWayland)

## Requirements

- [Bun](https://bun.sh) runtime
- Firefox browser
- `wmctrl` for window positioning: `sudo apt install wmctrl`
- Linux with systemd (for service installation)

## Usage

### Manual Run

```bash
bun run start -- "your command here"
```

Example:
```bash
bun run start -- "node server.js"
```

### Install as System Service

1. **Install the service:**
   ```bash
   sudo ./install.sh
   ```
   - You'll be prompted to enter the command to run
   - The service will be configured to start on boot

2. **Start the service:**
   ```bash
   sudo systemctl start hope-terminal
   ```

3. **Check status:**
   ```bash
   sudo systemctl status hope-terminal
   ```

4. **View logs:**
   ```bash
   sudo journalctl -u hope-terminal -f
   ```

### Uninstall Service

```bash
sudo ./uninstall.sh
```

## How It Works

1. On startup, detects if a secondary screen is connected
2. If found, launches Firefox in kiosk mode on that screen
3. Starts the user-provided command
4. Monitors for:
   - Screen connect/disconnect (every 5 seconds)
   - Browser closure (relaunches automatically)
   - Command exit (restarts after 5 seconds)
   - AC power disconnect (triggers shutdown sequence)

### Power Disconnect Sequence

When AC power is disconnected:
1. Sends SIGINT to the running command
2. Waits for the command to exit
3. Closes the browser
4. Shuts down the system

## Configuration

The target URL for the browser is configured in `src/browser.ts`:
```typescript
const TARGET_URL = "https://theopenpresenter.com/o/hope-newcastle/latest/render";
```

## License

MIT
