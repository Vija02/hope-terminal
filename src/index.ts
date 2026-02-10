// Hope Terminal - Kiosk Display Manager with Power-Off Handling
//
// Usage: bun run src/index.ts -- "command to run"
//
// This program:
// 1. Detects secondary screen using xrandr
// 2. Opens Chromium in kiosk mode on secondary screen (if found)
// 3. Starts the provided command simultaneously
// 4. Monitors AC power status
// 5. When power is disconnected:
//    - Sends SIGINT to the command
//    - Waits up to 5 minutes for graceful exit
//    - Closes the browser
//    - Shuts down the laptop

import { findSecondaryScreen, type ScreenInfo } from "./screen-detect.ts";
import { launchBrowser, type BrowserInstance } from "./browser.ts";
import { startProcess, type ManagedProcess } from "./process-manager.ts";
import { startPowerMonitor } from "./power-monitor.ts";

// Screen detection interval (5 seconds)
const SCREEN_DETECT_INTERVAL_MS = 5000;

// State
let browser: BrowserInstance | null = null;
let managedProcess: ManagedProcess | null = null;
let isShuttingDown = false;
let currentScreenName: string | null = null;
let screenMonitorInterval: Timer | null = null;

/**
 * Parse command line arguments
 */
function getCommand(): string | null {
  // bun run src/index.ts -- "command"
  // argv: [bun, src/index.ts, --, command]
  const args = process.argv.slice(2);
  
  // Find everything after --
  const dashDashIndex = args.indexOf("--");
  if (dashDashIndex !== -1 && dashDashIndex + 1 < args.length) {
    return args.slice(dashDashIndex + 1).join(" ");
  }
  
  // Or just take the first argument if no --
  if (args.length > 0 && args[0] !== "--") {
    return args.join(" ");
  }
  
  return null;
}

/**
 * Execute system shutdown
 */
async function executeShutdown(): Promise<void> {
  console.log("\n[Main] Executing system shutdown...");
  
  try {
    const proc = Bun.spawn(["sudo", "shutdown", "now"], {
      stdout: "inherit",
      stderr: "inherit",
    });
    
    await proc.exited;
  } catch (error) {
    console.error("[Main] Shutdown failed:", error);
    console.error("[Main] You may need to configure passwordless sudo for shutdown");
    console.error("[Main] Add to /etc/sudoers: %sudo ALL=(ALL) NOPASSWD: /sbin/shutdown");
  }
}

/**
 * Handle power disconnect - graceful shutdown sequence
 */
async function handlePowerDisconnect(): Promise<void> {
  if (isShuttingDown) {
    console.log("[Main] Already shutting down, ignoring...");
    return;
  }
  
  isShuttingDown = true;
  
  console.log("\n========================================");
  console.log("  POWER DISCONNECTED - SHUTTING DOWN");
  console.log("========================================\n");
  
  // Stop screen monitoring first
  stopScreenMonitor();
  
  // 1. Send SIGINT and wait for the command to exit
  if (managedProcess && managedProcess.isRunning()) {
    console.log("[Main] Step 1: Sending SIGINT to user command...");
    managedProcess.process.kill("SIGINT");
    await managedProcess.process.exited;
    console.log("[Main] Step 1: User command exited");
  } else {
    console.log("[Main] Step 1: No running command to stop");
  }
  
  // 2. Close browser
  if (browser) {
    console.log("[Main] Step 2: Closing browser...");
    await browser.close();
    browser = null;
    console.log("[Main] Step 2: Browser closed");
  } else {
    console.log("[Main] Step 2: No browser to close");
  }
  
  // 3. Shutdown the system
  console.log("[Main] Step 3: Shutting down system...");
  await executeShutdown();
  
  // If shutdown command didn't kill us, exit manually
  process.exit(0);
}

/**
 * Check if browser is still running
 */
function isBrowserRunning(): boolean {
  return browser !== null && browser.process.exitCode === null;
}

/**
 * Start continuous screen monitoring
 * Launches browser when secondary screen is detected, closes when disconnected
 * Also relaunches browser if it was closed (e.g., Alt+F4)
 */
function startScreenMonitor(): void {
  console.log(`[Main] Starting screen monitor (checking every ${SCREEN_DETECT_INTERVAL_MS / 1000}s)...`);
  
  screenMonitorInterval = setInterval(async () => {
    if (isShuttingDown) {
      return;
    }
    
    const secondaryScreen = await findSecondaryScreen();
    
    // Screen connected but no browser (or browser was closed)
    if (secondaryScreen && !isBrowserRunning()) {
      if (browser) {
        // Browser was closed (e.g., Alt+F4)
        console.log(`\n[Main] Browser was closed, relaunching on ${secondaryScreen.name}...`);
        browser = null;
      } else {
        console.log(`\n[Main] Secondary screen detected: ${secondaryScreen.name}`);
      }
      
      currentScreenName = secondaryScreen.name;
      browser = await launchBrowser(secondaryScreen);
      
      if (!browser) {
        console.warn("[Main] Failed to launch browser on screen");
      }
    }
    // Screen disconnected
    else if (!secondaryScreen && browser) {
      console.log(`\n[Main] Secondary screen disconnected (was: ${currentScreenName})`);
      if (isBrowserRunning()) {
        await browser.close();
      }
      browser = null;
      currentScreenName = null;
    }
    // Screen changed (different screen connected)
    else if (secondaryScreen && isBrowserRunning() && secondaryScreen.name !== currentScreenName) {
      console.log(`\n[Main] Screen changed from ${currentScreenName} to ${secondaryScreen.name}`);
      await browser!.close();
      currentScreenName = secondaryScreen.name;
      browser = await launchBrowser(secondaryScreen);
      
      if (!browser) {
        console.warn("[Main] Failed to launch browser on new screen");
      }
    }
  }, SCREEN_DETECT_INTERVAL_MS);
}

/**
 * Stop screen monitoring
 */
function stopScreenMonitor(): void {
  if (screenMonitorInterval) {
    clearInterval(screenMonitorInterval);
    screenMonitorInterval = null;
  }
}

/**
 * Handle manual termination (Ctrl+C on this script)
 */
async function handleManualTermination(): Promise<void> {
  if (isShuttingDown) {
    console.log("\n[Main] Force exiting...");
    process.exit(1);
  }
  
  isShuttingDown = true;
  console.log("\n[Main] Received termination signal, cleaning up...");
  
  // Stop screen monitoring
  stopScreenMonitor();
  
  // Stop the managed process
  if (managedProcess && managedProcess.isRunning()) {
    await managedProcess.gracefulStop();
  }
  
  // Close browser
  if (browser) {
    await browser.close();
  }
  
  console.log("[Main] Cleanup complete, exiting");
  process.exit(0);
}

/**
 * Main entry point
 */
async function main(): Promise<void> {
  console.log("========================================");
  console.log("     Hope Terminal - Kiosk Manager");
  console.log("========================================\n");
  
  // Parse command
  const command = getCommand();
  
  if (!command) {
    console.error("Usage: bun run src/index.ts -- \"command to run\"");
    console.error("Example: bun run src/index.ts -- \"node server.js\"");
    process.exit(1);
  }
  
  console.log(`[Main] Command to run: ${command}\n`);
  
  // Set up signal handlers
  process.on("SIGINT", handleManualTermination);
  process.on("SIGTERM", handleManualTermination);
  
  // Step 1: Initial screen detection
  console.log("[Main] Step 1: Detecting screens...");
  const secondaryScreen = await findSecondaryScreen();
  
  // Step 2: Launch browser on secondary screen (if found) and start monitoring
  if (secondaryScreen) {
    console.log("\n[Main] Step 2: Launching browser on secondary screen...");
    currentScreenName = secondaryScreen.name;
    browser = await launchBrowser(secondaryScreen);
    
    if (!browser) {
      console.warn("[Main] Failed to launch browser, will retry when screen is detected");
    }
  } else {
    console.log("\n[Main] Step 2: No secondary screen found, will monitor for connection");
  }
  
  // Start continuous screen monitoring
  startScreenMonitor();
  
  // Step 3: Start user command (simultaneously with browser)
  console.log("\n[Main] Step 3: Starting user command...");
  managedProcess = startProcess(command);
  
  // Step 4: Start power monitoring
  console.log("\n[Main] Step 4: Starting power monitor...");
  const powerMonitor = await startPowerMonitor({
    pollInterval: 2000,
    onPowerDisconnect: handlePowerDisconnect,
  });
  
  console.log("\n========================================");
  console.log("  System running - Press Ctrl+C to stop");
  console.log("  Power disconnect will trigger shutdown");
  console.log("========================================\n");
  
  // Auto-restart loop
  const RESTART_DELAY_MS = 5000;
  
  while (!isShuttingDown) {
    // Wait for the managed process to exit
    await managedProcess.process.exited;
    
    const exitCode = managedProcess.getExitCode();
    console.log(`\n[Main] User command exited with code ${exitCode}`);
    
    // If we're shutting down, don't restart
    if (isShuttingDown) {
      break;
    }
    
    // Wait before restarting
    console.log(`[Main] Restarting command in ${RESTART_DELAY_MS / 1000} seconds...`);
    await new Promise((resolve) => setTimeout(resolve, RESTART_DELAY_MS));
    
    // Check again after the delay
    if (isShuttingDown) {
      break;
    }
    
    // Restart the process
    console.log("[Main] Restarting user command...");
    managedProcess = startProcess(command);
  }
  
  // Clean up when loop exits (only if not already shutting down from power disconnect)
  if (!isShuttingDown) {
    powerMonitor.stop();
    stopScreenMonitor();
    
    if (browser) {
      await browser.close();
    }
    
    process.exit(managedProcess?.getExitCode() ?? 0);
  }
  
  // If we're here due to shutdown, just wait (handlePowerDisconnect will handle exit)
  powerMonitor.stop();
}

// Run
main().catch((error) => {
  console.error("[Main] Fatal error:", error);
  process.exit(1);
});
