// Power Monitor - Detects when AC power is disconnected
// 
// On Ubuntu laptops, battery status is exposed via sysfs:
// /sys/class/power_supply/BAT0/status
// 
// Values: "Charging", "Discharging", "Full", "Not charging"

import { readdir } from "node:fs/promises";

export type PowerStatus = "ac" | "battery" | "unknown";

export interface PowerMonitorOptions {
  /** Polling interval in milliseconds (default: 2000) */
  pollInterval?: number;
  /** Callback when power status changes from AC to battery */
  onPowerDisconnect: () => void;
}

const POWER_SUPPLY_PATH = "/sys/class/power_supply";

/**
 * Find the battery status path in /sys/class/power_supply
 * Common names: BAT0, BAT1
 */
async function findBatteryStatusPath(): Promise<string | null> {
  try {
    const entries = await readdir(POWER_SUPPLY_PATH);
    
    // Look for battery
    const batteryPatterns = ["BAT"];
    
    for (const entry of entries) {
      const isBattery = batteryPatterns.some(pattern => 
        entry.toUpperCase().startsWith(pattern)
      );
      
      if (isBattery) {
        const statusPath = `${POWER_SUPPLY_PATH}/${entry}/status`;
        const file = Bun.file(statusPath);
        if (await file.exists()) {
          return statusPath;
        }
      }
    }
    
    return null;
  } catch {
    return null;
  }
}

/**
 * Read current power status from battery status file
 * "Charging" or "Full" or "Not charging" = on AC
 * "Discharging" = on battery
 */
async function readPowerStatus(batteryStatusPath: string): Promise<PowerStatus> {
  try {
    const file = Bun.file(batteryStatusPath);
    const content = await file.text();
    const value = content.trim().toLowerCase();
    
    if (value === "discharging") return "battery";
    if (value === "charging" || value === "full" || value === "not charging") return "ac";
    return "unknown";
  } catch {
    return "unknown";
  }
}

/**
 * Start monitoring power status
 * Returns a function to stop monitoring
 */
export async function startPowerMonitor(options: PowerMonitorOptions): Promise<{
  stop: () => void;
  getStatus: () => PowerStatus;
}> {
  const pollInterval = options.pollInterval ?? 2000;
  
  const batteryStatusPath = await findBatteryStatusPath();
  
  if (!batteryStatusPath) {
    console.warn("[PowerMonitor] No battery found in /sys/class/power_supply");
    console.warn("[PowerMonitor] Power monitoring disabled - running without power detection");
    
    return {
      stop: () => {},
      getStatus: () => "unknown",
    };
  }
  
  console.log(`[PowerMonitor] Found battery status at: ${batteryStatusPath}`);
  
  let currentStatus = await readPowerStatus(batteryStatusPath);
  let isRunning = true;
  let timeoutId: ReturnType<typeof setTimeout> | null = null;
  
  console.log(`[PowerMonitor] Initial power status: ${currentStatus}`);
  
  const poll = async () => {
    if (!isRunning) return;
    
    const newStatus = await readPowerStatus(batteryStatusPath);
    
    // Detect transition from AC to battery
    if (currentStatus === "ac" && newStatus === "battery") {
      console.log("[PowerMonitor] Power disconnected! Triggering shutdown sequence...");
      options.onPowerDisconnect();
    }
    
    currentStatus = newStatus;
    
    if (isRunning) {
      timeoutId = setTimeout(poll, pollInterval);
    }
  };
  
  // Start polling
  timeoutId = setTimeout(poll, pollInterval);
  
  return {
    stop: () => {
      isRunning = false;
      if (timeoutId) {
        clearTimeout(timeoutId);
        timeoutId = null;
      }
      console.log("[PowerMonitor] Stopped");
    },
    getStatus: () => currentStatus,
  };
}
