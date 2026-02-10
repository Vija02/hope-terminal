// Browser - Launch Chromium in kiosk mode on secondary screen

import type { Subprocess } from "bun";
import type { ScreenInfo } from "./screen-detect.ts";

const TARGET_URL = "https://theopenpresenter.com/o/hope-newcastle/latest/render";

// Chromium browser executables to try (in order of preference)
const CHROMIUM_EXECUTABLES = [
  "chromium-browser",
  "chromium",
  "google-chrome",
  "google-chrome-stable",
];

/**
 * Find available Chromium executable
 */
async function findChromiumExecutable(): Promise<string | null> {
  for (const exe of CHROMIUM_EXECUTABLES) {
    try {
      const proc = Bun.spawn(["which", exe], {
        stdout: "pipe",
        stderr: "pipe",
      });
      
      const exitCode = await proc.exited;
      if (exitCode === 0) {
        console.log(`[Browser] Found browser: ${exe}`);
        return exe;
      }
    } catch {
      // Continue to next
    }
  }
  
  return null;
}

export interface BrowserInstance {
  process: Subprocess;
  close: () => Promise<void>;
}

/**
 * Launch Chromium in kiosk mode on the specified screen
 */
export async function launchBrowser(screen: ScreenInfo): Promise<BrowserInstance | null> {
  const chromium = await findChromiumExecutable();
  
  if (!chromium) {
    console.error("[Browser] No Chromium/Chrome browser found!");
    console.error("[Browser] Please install chromium-browser: sudo apt install chromium-browser");
    return null;
  }
  
  const args = [
    chromium,
    // Kiosk mode
    "--kiosk",
    // Allow autoplay without user gesture
    "--autoplay-policy=no-user-gesture-required",
    // Position on secondary screen
    `--window-position=${screen.xOffset},${screen.yOffset}`,
    // Fullscreen size matching screen
    `--window-size=${screen.width},${screen.height}`,
    // Disable various UI elements and popups
    "--disable-infobars",
    "--disable-session-crashed-bubble",
    "--disable-restore-session-state",
    "--noerrdialogs",
    "--disable-translate",
    "--no-first-run",
    "--fast",
    "--fast-start",
    "--disable-features=TranslateUI",
    // Disable password manager prompts
    "--disable-save-password-bubble",
    // Start maximized
    "--start-maximized",
    // Disable GPU if it causes issues (uncomment if needed)
    // "--disable-gpu",
    // The URL to open
    TARGET_URL,
  ];
  
  console.log(`[Browser] Launching ${chromium} in kiosk mode on ${screen.name}`);
  console.log(`[Browser] Position: ${screen.xOffset},${screen.yOffset}, Size: ${screen.width}x${screen.height}`);
  console.log(`[Browser] URL: ${TARGET_URL}`);
  
  const process = Bun.spawn(args, {
    stdout: "ignore",
    stderr: "ignore",
  });
  
  // Give the browser a moment to start
  await new Promise((resolve) => setTimeout(resolve, 1000));
  
  // Check if it crashed immediately
  if (process.exitCode !== null) {
    console.error(`[Browser] Browser exited immediately with code ${process.exitCode}`);
    return null;
  }
  
  console.log(`[Browser] Browser started with PID: ${process.pid}`);
  
  return {
    process,
    close: async () => {
      console.log("[Browser] Closing browser...");
      
      // Try graceful termination first
      process.kill("SIGTERM");
      
      // Wait up to 5 seconds for graceful exit
      const timeout = 5000;
      const startTime = Date.now();
      
      while (process.exitCode === null && Date.now() - startTime < timeout) {
        await new Promise((resolve) => setTimeout(resolve, 100));
      }
      
      // Force kill if still running
      if (process.exitCode === null) {
        console.log("[Browser] Force killing browser...");
        process.kill("SIGKILL");
      }
      
      console.log("[Browser] Browser closed");
    },
  };
}
