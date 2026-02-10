// Screen Detection - Detect secondary screen using xrandr

export interface ScreenInfo {
  name: string;
  width: number;
  height: number;
  xOffset: number;
  yOffset: number;
  isPrimary: boolean;
}

/**
 * Parse xrandr output to find connected screens
 * 
 * Example xrandr output line:
 * HDMI-1 connected 1920x1080+1920+0 (normal left inverted right x axis y axis) 527mm x 296mm
 * eDP-1 connected primary 1920x1080+0+0 (normal left inverted right x axis y axis) 344mm x 194mm
 */
function parseXrandrOutput(output: string): ScreenInfo[] {
  const screens: ScreenInfo[] = [];
  const lines = output.split("\n");
  
  for (const line of lines) {
    // Match connected screens with resolution
    // Pattern: <name> connected [primary] <width>x<height>+<x>+<y>
    const match = line.match(
      /^(\S+)\s+connected\s+(primary\s+)?(\d+)x(\d+)\+(\d+)\+(\d+)/
    );
    
    if (match) {
      const [, name, primary, width, height, xOffset, yOffset] = match;
      screens.push({
        name: name!,
        width: parseInt(width!, 10),
        height: parseInt(height!, 10),
        xOffset: parseInt(xOffset!, 10),
        yOffset: parseInt(yOffset!, 10),
        isPrimary: !!primary,
      });
    }
  }
  
  return screens;
}

/**
 * Detect all connected screens using xrandr
 */
export async function detectScreens(): Promise<ScreenInfo[]> {
  try {
    const proc = Bun.spawn(["xrandr", "--query"], {
      stdout: "pipe",
      stderr: "pipe",
    });
    
    const output = await new Response(proc.stdout).text();
    const exitCode = await proc.exited;
    
    if (exitCode !== 0) {
      const stderr = await new Response(proc.stderr).text();
      console.error("[ScreenDetect] xrandr failed:", stderr);
      return [];
    }
    
    return parseXrandrOutput(output);
  } catch (error) {
    console.error("[ScreenDetect] Failed to run xrandr:", error);
    return [];
  }
}

/**
 * Find a secondary (non-primary) screen
 */
export async function findSecondaryScreen(): Promise<ScreenInfo | null> {
  const screens = await detectScreens();
  
  console.log(`[ScreenDetect] Found ${screens.length} connected screen(s)`);
  
  for (const screen of screens) {
    console.log(
      `  - ${screen.name}: ${screen.width}x${screen.height}+${screen.xOffset}+${screen.yOffset}${screen.isPrimary ? " (primary)" : ""}`
    );
  }
  
  // Find first non-primary screen
  const secondary = screens.find((s) => !s.isPrimary);
  
  if (secondary) {
    console.log(`[ScreenDetect] Using secondary screen: ${secondary.name}`);
    return secondary;
  }
  
  // If only one screen and it's marked primary, return null
  if (screens.length === 1) {
    console.log("[ScreenDetect] Only one screen detected, no secondary screen available");
    return null;
  }
  
  // If multiple screens but none marked as secondary, use the one with higher x offset
  if (screens.length > 1) {
    const sorted = [...screens].sort((a, b) => b.xOffset - a.xOffset);
    const rightmost = sorted[0]!;
    console.log(`[ScreenDetect] Using rightmost screen as secondary: ${rightmost.name}`);
    return rightmost;
  }
  
  return null;
}
