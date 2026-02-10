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
 * Move window to specified screen using xdotool
 */
async function moveWindowToScreen(pid: number, screen: ScreenInfo): Promise<boolean> {
  try {
    // Wait a bit for the window to be created
    await new Promise((resolve) => setTimeout(resolve, 500));
    
    // Find window by PID
    const searchProc = Bun.spawn(["xdotool", "search", "--pid", String(pid)], {
      stdout: "pipe",
      stderr: "pipe",
    });
    
    const windowIds = (await new Response(searchProc.stdout).text()).trim().split("\n").filter(Boolean);
    await searchProc.exited;
    
    if (windowIds.length === 0) {
      console.warn("[Browser] Could not find window by PID, trying by name...");
      
      // Fallback: search by window name
      const nameSearchProc = Bun.spawn(["xdotool", "search", "--name", "Chromium"], {
        stdout: "pipe",
        stderr: "pipe",
      });
      
      const nameWindowIds = (await new Response(nameSearchProc.stdout).text()).trim().split("\n").filter(Boolean);
      await nameSearchProc.exited;
      
      if (nameWindowIds.length === 0) {
        console.error("[Browser] Could not find any browser window");
        return false;
      }
      
      windowIds.push(...nameWindowIds);
    }
    
    // Move each window (usually just one, but handle multiple tabs)
    for (const windowId of windowIds) {
      console.log(`[Browser] Moving window ${windowId} to position ${screen.xOffset},${screen.yOffset}`);
      
      // Remove maximized state first
      const unmaxProc = Bun.spawn(["wmctrl", "-i", "-r", windowId, "-b", "remove,maximized_vert,maximized_horz"], {
        stdout: "ignore",
        stderr: "ignore",
      });
      await unmaxProc.exited;
      
      // Move and resize the window
      const moveProc = Bun.spawn([
        "xdotool",
        "windowmove",
        windowId,
        String(screen.xOffset),
        String(screen.yOffset),
      ], {
        stdout: "ignore",
        stderr: "pipe",
      });
      await moveProc.exited;
      
      const resizeProc = Bun.spawn([
        "xdotool",
        "windowsize",
        windowId,
        String(screen.width),
        String(screen.height),
      ], {
        stdout: "ignore",
        stderr: "pipe",
      });
      await resizeProc.exited;
      
      // Make it fullscreen
      const fullscreenProc = Bun.spawn(["wmctrl", "-i", "-r", windowId, "-b", "add,fullscreen"], {
        stdout: "ignore",
        stderr: "ignore",
      });
      await fullscreenProc.exited;
    }
    
    return true;
  } catch (error) {
    console.error("[Browser] Failed to move window:", error);
    return false;
  }
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
    // Don't use kiosk mode initially - we'll fullscreen after moving
    // "--kiosk",
    // Allow autoplay without user gesture
    "--autoplay-policy=no-user-gesture-required",
    // Position on secondary screen (hint, may not work reliably)
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
    // New window
    "--new-window",
    // Disable GPU if it causes issues (uncomment if needed)
    // "--disable-gpu",
    // The URL to open
    TARGET_URL,
  ];
  
  console.log(`[Browser] Launching ${chromium} on ${screen.name}`);
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
  
  // Move window to correct screen using xdotool
  const moved = await moveWindowToScreen(process.pid, screen);
  if (!moved) {
    console.warn("[Browser] Could not move window to secondary screen, it may be on the wrong display");
    console.warn("[Browser] Install xdotool and wmctrl: sudo apt install xdotool wmctrl");
  }
  
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
