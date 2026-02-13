// Clicker Remap - Forward presentation clicker keys to Firefox window
//
// Usage: bun run src/clicker-remap.ts [--device "Device Name"]
//
// This program:
// 1. Finds the presentation clicker input device
// 2. Grabs it exclusively (prevents original keys from passing through)
// 3. Forwards key events to the Firefox window on the secondary screen

import {
  InputDeviceReader,
  findInputDevice,
  findInputDevicesByPattern,
  listInputDevices,
  EV_KEY,
  KEY_NAMES,
} from "./evdev.ts";
import { findFirefoxWindow } from "./browser.ts";

// Default device name to look for
const DEFAULT_DEVICE_NAME = "USB RF PRESENT";

// Retry settings for finding Firefox window
const FIREFOX_RETRY_INTERVAL_MS = 2000;

// State
let reader: InputDeviceReader | null = null;
let isShuttingDown = false;
let cachedFirefoxWindowId: string | null = null;

/**
 * Parse command line arguments
 */
function parseArgs(): { deviceName: string; listDevices: boolean } {
  const args = process.argv.slice(2);
  let deviceName = DEFAULT_DEVICE_NAME;
  let listDevices = false;

  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--device" && args[i + 1]) {
      deviceName = args[i + 1]!;
      i++;
    } else if (args[i] === "--list") {
      listDevices = true;
    }
  }

  return { deviceName, listDevices };
}

/**
 * Send a key to the Firefox window using xdotool
 */
async function sendKeyToFirefox(keyName: string): Promise<boolean> {
  // Try to use cached window ID first
  let windowId = cachedFirefoxWindowId;

  // If no cached ID or sending fails, refresh the window ID
  if (!windowId) {
    windowId = await findFirefoxWindow(3, 500);
    if (windowId) {
      cachedFirefoxWindowId = windowId;
      console.log(`[Clicker] Found Firefox window: ${windowId}`);
    }
  }

  if (!windowId) {
    console.warn("[Clicker] Firefox window not found, skipping key event");
    return false;
  }

  try {
    const proc = Bun.spawn(["xdotool", "key", "--window", windowId, keyName], {
      stdout: "pipe",
      stderr: "pipe",
    });

    const exitCode = await proc.exited;

    if (exitCode !== 0) {
      // Window might have been closed, clear cache
      cachedFirefoxWindowId = null;
      const stderr = await new Response(proc.stderr).text();
      console.warn(`[Clicker] xdotool failed (exit ${exitCode}): ${stderr}`);
      return false;
    }

    console.log(`[Clicker] Sent key '${keyName}' to Firefox`);
    return true;
  } catch (error) {
    cachedFirefoxWindowId = null;
    console.error("[Clicker] Failed to send key:", error);
    return false;
  }
}

/**
 * Main event loop
 */
async function eventLoop(): Promise<void> {
  if (!reader) return;

  console.log("[Clicker] Starting event loop...");
  console.log("[Clicker] Listening for key events (Ctrl+C to stop)");

  while (!isShuttingDown) {
    const event = await reader.readEvent();

    if (event === null) {
      if (!isShuttingDown) {
        console.error("[Clicker] Device disconnected or error occurred");
      }
      break;
    }

    // Only process key press events (not release or repeat)
    if (event.type === EV_KEY && event.value === 1) {
      const keyName = KEY_NAMES[event.code];

      if (keyName) {
        console.log(
          `[Clicker] Key press detected: code=${event.code} (${keyName})`
        );
        await sendKeyToFirefox(keyName);
      } else {
        console.log(
          `[Clicker] Unknown key press: code=${event.code} (not forwarding)`
        );
      }
    }
  }
}

/**
 * Graceful shutdown
 */
async function shutdown(): Promise<void> {
  if (isShuttingDown) return;
  isShuttingDown = true;

  console.log("\n[Clicker] Shutting down...");

  if (reader) {
    await reader.close();
    reader = null;
  }

  console.log("[Clicker] Goodbye!");
  process.exit(0);
}

/**
 * Main entry point
 */
async function main(): Promise<void> {
  console.log("========================================");
  console.log("  Clicker Remap - Key Forwarding Tool");
  console.log("========================================\n");

  const { deviceName, listDevices } = parseArgs();

  // List devices mode
  if (listDevices) {
    console.log("[Clicker] Listing all input devices:\n");
    const devices = await listInputDevices();

    for (const device of devices) {
      const hasEvent = device.eventPath ? "yes" : "no";
      console.log(`  Name: "${device.name}"`);
      console.log(`    Event path: ${device.eventPath || "N/A"}`);
      console.log(`    Handlers: ${device.handlers.join(", ")}`);
      console.log();
    }

    console.log(`Total: ${devices.length} devices`);
    console.log("\nUsage: bun run src/clicker-remap.ts --device \"Device Name\"");
    return;
  }

  // Set up signal handlers
  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);

  // Find the device
  console.log(`[Clicker] Looking for device: "${deviceName}"`);

  let device = await findInputDevice(deviceName);

  // If exact match not found, try pattern match
  if (!device) {
    const matches = await findInputDevicesByPattern(deviceName);
    if (matches.length > 0) {
      // Use the first match that has "kbd" in handlers (keyboard device)
      device =
        matches.find((d) => d.handlers.some((h) => h === "kbd")) || matches[0]!;
      console.log(`[Clicker] Found device by pattern: "${device.name}"`);
    }
  }

  if (!device || !device.eventPath) {
    console.error(`[Clicker] Device not found: "${deviceName}"`);
    console.error("\nAvailable devices with keyboard input:");

    const devices = await listInputDevices();
    const kbdDevices = devices.filter(
      (d) => d.handlers.some((h) => h === "kbd") && d.eventPath
    );

    for (const d of kbdDevices) {
      console.error(`  - "${d.name}" (${d.eventPath})`);
    }

    console.error("\nRun with --list to see all devices");
    console.error('Or specify device: --device "Device Name"');
    process.exit(1);
  }

  console.log(`[Clicker] Using device: ${device.name}`);
  console.log(`[Clicker] Event path: ${device.eventPath}`);

  // Open the device with exclusive grab
  reader = new InputDeviceReader(device.eventPath, device.name);

  const opened = await reader.open(true);
  if (!opened) {
    console.error("[Clicker] Failed to open device");
    console.error("\nMake sure you have permission to read /dev/input devices:");
    console.error("  sudo usermod -aG input $USER");
    console.error("  (logout and login again)");
    console.error("\nOr run with sudo:");
    console.error("  sudo bun run src/clicker-remap.ts");
    process.exit(1);
  }

  // Check if Firefox is already running
  const firefoxWindow = await findFirefoxWindow(3, 500);
  if (firefoxWindow) {
    cachedFirefoxWindowId = firefoxWindow;
    console.log(`[Clicker] Firefox window found: ${firefoxWindow}`);
  } else {
    console.log("[Clicker] Firefox window not found yet (will retry on key press)");
  }

  console.log("\n========================================");
  console.log("  Ready! Press clicker buttons...");
  console.log("========================================\n");

  // Start event loop
  await eventLoop();

  // Clean up on exit
  await shutdown();
}

// Run
main().catch((error) => {
  console.error("[Clicker] Fatal error:", error);
  process.exit(1);
});
