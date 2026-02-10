// Process Manager - Manage child process with graceful shutdown

import type { Subprocess } from "bun";

// 5 minute timeout for graceful shutdown
const GRACEFUL_TIMEOUT_MS = 5 * 60 * 1000;

export interface ManagedProcess {
  process: Subprocess;
  /** Send SIGINT and wait for graceful exit (up to 5 minutes) */
  gracefulStop: () => Promise<boolean>;
  /** Check if process is still running */
  isRunning: () => boolean;
  /** Get the exit code (null if still running) */
  getExitCode: () => number | null;
}

/**
 * Parse command string into executable and arguments
 * Handles quoted arguments
 */
function parseCommand(command: string): string[] {
  const parts: string[] = [];
  let current = "";
  let inQuote = false;
  let quoteChar = "";
  
  for (let i = 0; i < command.length; i++) {
    const char = command[i]!;
    
    if (inQuote) {
      if (char === quoteChar) {
        inQuote = false;
      } else {
        current += char;
      }
    } else if (char === '"' || char === "'") {
      inQuote = true;
      quoteChar = char;
    } else if (char === " " || char === "\t") {
      if (current) {
        parts.push(current);
        current = "";
      }
    } else {
      current += char;
    }
  }
  
  if (current) {
    parts.push(current);
  }
  
  return parts;
}

/**
 * Start a managed process from a command string
 */
export function startProcess(command: string): ManagedProcess {
  const parts = parseCommand(command);
  
  if (parts.length === 0) {
    throw new Error("Empty command provided");
  }
  
  console.log(`[ProcessManager] Starting command: ${command}`);
  console.log(`[ProcessManager] Parsed as: ${JSON.stringify(parts)}`);
  
  const process = Bun.spawn(parts, {
    stdout: "inherit",
    stderr: "inherit",
    stdin: "inherit",
  });
  
  console.log(`[ProcessManager] Process started with PID: ${process.pid}`);
  
  return {
    process,
    
    isRunning: () => process.exitCode === null,
    
    getExitCode: () => process.exitCode,
    
    gracefulStop: async () => {
      if (process.exitCode !== null) {
        console.log(`[ProcessManager] Process already exited with code ${process.exitCode}`);
        return true;
      }
      
      console.log("[ProcessManager] Sending SIGINT (Ctrl+C) to process...");
      process.kill("SIGINT");
      
      const startTime = Date.now();
      
      // Poll for exit
      while (process.exitCode === null) {
        const elapsed = Date.now() - startTime;
        
        if (elapsed >= GRACEFUL_TIMEOUT_MS) {
          console.log(`[ProcessManager] Timeout after ${GRACEFUL_TIMEOUT_MS / 1000}s, force killing...`);
          process.kill("SIGKILL");
          
          // Wait a bit for force kill to take effect
          await new Promise((resolve) => setTimeout(resolve, 1000));
          return false;
        }
        
        // Log progress every 30 seconds
        if (elapsed > 0 && elapsed % 30000 < 100) {
          const remaining = Math.round((GRACEFUL_TIMEOUT_MS - elapsed) / 1000);
          console.log(`[ProcessManager] Waiting for graceful exit... ${remaining}s remaining`);
        }
        
        await new Promise((resolve) => setTimeout(resolve, 100));
      }
      
      console.log(`[ProcessManager] Process exited gracefully with code ${process.exitCode}`);
      return true;
    },
  };
}
