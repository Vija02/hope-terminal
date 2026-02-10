// Power Monitor - Detects when AC power is disconnected
// 
// On Ubuntu laptops, power supply status is exposed via sysfs:
// /sys/class/power_supply/AC0/online or /sys/class/power_supply/ACAD/online
// 
// Value: 1 = plugged in, 0 = on battery

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
 * Find the AC adapter path in /sys/class/power_supply
 * Common names: AC, AC0, ACAD, ADP0, ADP1
 */
async function findAcAdapterPath(): Promise<string | null> {
  try {
    const entries = await readdir(POWER_SUPPLY_PATH);
    
    // Look for AC adapter (not battery)
    const acPatterns = ["AC", "ACAD", "ADP"];
    
    for (const entry of entries) {
      const isAcAdapter = acPatterns.some(pattern => 
        entry.toUpperCase().startsWith(pattern)
      );
      
      if (isAcAdapter) {
        const onlinePath = `${POWER_SUPPLY_PATH}/${entry}/online`;
        const file = Bun.file(onlinePath);
        if (await file.exists()) {
          return onlinePath;
        }
      }
    }
    
    // Fallback: check for any device with an "online" file
    for (const entry of entries) {
      const onlinePath = `${POWER_SUPPLY_PATH}/${entry}/online`;
      const file = Bun.file(onlinePath);
      if (await file.exists()) {
        return onlinePath;
      }
    }
    
    return null;
  } catch {
    return null;
  }
}

/**
 * Read current power status
 */
async function readPowerStatus(acPath: string): Promise<PowerStatus> {
  try {
    const file = Bun.file(acPath);
    const content = await file.text();
    const value = content.trim();
    
    if (value === "1") return "ac";
    if (value === "0") return "battery";
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
  
  const acPath = await findAcAdapterPath();
  
  if (!acPath) {
    console.warn("[PowerMonitor] No AC adapter found in /sys/class/power_supply");
    console.warn("[PowerMonitor] Power monitoring disabled - running without power detection");
    
    return {
      stop: () => {},
      getStatus: () => "unknown",
    };
  }
  
  console.log(`[PowerMonitor] Found AC adapter at: ${acPath}`);
  
  let currentStatus = await readPowerStatus(acPath);
  let isRunning = true;
  let timeoutId: ReturnType<typeof setTimeout> | null = null;
  
  console.log(`[PowerMonitor] Initial power status: ${currentStatus}`);
  
  const poll = async () => {
    if (!isRunning) return;
    
    const newStatus = await readPowerStatus(acPath);
    
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
