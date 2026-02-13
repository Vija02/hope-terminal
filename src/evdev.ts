// Evdev - Low-level Linux input device reader
//
// This module provides functionality to:
// 1. Find input devices by name from /proc/bus/input/devices
// 2. Open /dev/input/eventX with exclusive grab (EVIOCGRAB)
// 3. Read raw input_event structs and emit key events

import { dlopen, FFIType } from "bun:ffi";

// Linux input event constants
export const EV_KEY = 1;

// Common key codes for presentation clickers
export const KEY_UP = 103;
export const KEY_PAGEUP = 104;
export const KEY_DOWN = 108;
export const KEY_PAGEDOWN = 109;
export const KEY_F5 = 63;
export const KEY_ESC = 1;
export const KEY_LEFT = 105;
export const KEY_RIGHT = 106;

// Key code to xdotool key name mapping
export const KEY_NAMES: Record<number, string> = {
  [KEY_UP]: "Up",
  [KEY_PAGEUP]: "Page_Up",
  [KEY_DOWN]: "Down",
  [KEY_PAGEDOWN]: "Page_Down",
  [KEY_F5]: "F5",
  [KEY_ESC]: "Escape",
  [KEY_LEFT]: "Left",
  [KEY_RIGHT]: "Right",
};

// struct input_event on 64-bit Linux:
// struct timeval { long tv_sec; long tv_usec; } = 16 bytes
// __u16 type = 2 bytes
// __u16 code = 2 bytes
// __s32 value = 4 bytes
// Total = 24 bytes
const INPUT_EVENT_SIZE = 24;

// EVIOCGRAB ioctl number: _IOW('E', 0x90, int) = 0x40044590
const EVIOCGRAB = 0x40044590;

export interface InputEvent {
  type: number;
  code: number;
  value: number; // 0 = release, 1 = press, 2 = repeat
}

export interface InputDeviceInfo {
  name: string;
  handlers: string[];
  eventPath: string | null;
}

/**
 * Parse /proc/bus/input/devices to find all input devices
 */
export async function listInputDevices(): Promise<InputDeviceInfo[]> {
  const devices: InputDeviceInfo[] = [];

  try {
    const content = await Bun.file("/proc/bus/input/devices").text();
    const blocks = content.split("\n\n");

    for (const block of blocks) {
      if (!block.trim()) continue;

      const lines = block.split("\n");
      let name = "";
      let handlers: string[] = [];

      for (const line of lines) {
        // N: Name="USB RF PRESENT"
        const nameMatch = line.match(/^N: Name="(.+)"$/);
        if (nameMatch) {
          name = nameMatch[1]!;
        }

        // H: Handlers=sysrq kbd event7 leds
        const handlersMatch = line.match(/^H: Handlers=(.+)$/);
        if (handlersMatch) {
          handlers = handlersMatch[1]!.split(/\s+/);
        }
      }

      if (name) {
        // Find eventX handler
        const eventHandler = handlers.find((h) => h.startsWith("event"));
        devices.push({
          name,
          handlers,
          eventPath: eventHandler ? `/dev/input/${eventHandler}` : null,
        });
      }
    }
  } catch (error) {
    console.error("[Evdev] Failed to list input devices:", error);
  }

  return devices;
}

/**
 * Find an input device by exact name
 */
export async function findInputDevice(
  exactName: string
): Promise<InputDeviceInfo | null> {
  const devices = await listInputDevices();

  for (const device of devices) {
    if (device.name === exactName && device.eventPath) {
      return device;
    }
  }

  return null;
}

/**
 * Find input devices by name pattern (partial match)
 */
export async function findInputDevicesByPattern(
  namePattern: string
): Promise<InputDeviceInfo[]> {
  const devices = await listInputDevices();
  return devices.filter(
    (d) => d.name.includes(namePattern) && d.eventPath !== null
  );
}

// Load libc for ioctl
const libc = dlopen("libc.so.6", {
  ioctl: {
    args: [FFIType.i32, FFIType.u64, FFIType.i32],
    returns: FFIType.i32,
  },
});

/**
 * Input device reader with exclusive grab
 */
export class InputDeviceReader {
  private fd: number | null = null;
  private stream: ReadableStream<Uint8Array> | null = null;
  private reader: ReadableStreamDefaultReader<Uint8Array> | null = null;
  private buffer: Uint8Array = new Uint8Array(0);
  private grabbed: boolean = false;
  private closed: boolean = false;
  public devicePath: string;
  public deviceName: string;

  constructor(devicePath: string, deviceName: string = "unknown") {
    this.devicePath = devicePath;
    this.deviceName = deviceName;
  }

  /**
   * Open the device and optionally grab it exclusively
   */
  async open(grab: boolean = true): Promise<boolean> {
    try {
      const fs = await import("node:fs");

      // Open file descriptor for ioctl
      const fd = fs.openSync(this.devicePath, fs.constants.O_RDONLY);
      this.fd = fd;

      if (grab) {
        // Call ioctl to grab the device exclusively
        const result = libc.symbols.ioctl(fd, EVIOCGRAB, 1);
        if (result < 0) {
          console.warn(
            `[Evdev] Failed to grab device exclusively (ioctl returned ${result})`
          );
          console.warn(
            "[Evdev] Device will still work but original events may pass through"
          );
        } else {
          this.grabbed = true;
          console.log(`[Evdev] Grabbed device exclusively: ${this.devicePath}`);
        }
      }

      // Create readable stream from file
      const file = Bun.file(this.devicePath);
      this.stream = file.stream();
      this.reader = this.stream.getReader() as ReadableStreamDefaultReader<Uint8Array>;

      console.log(
        `[Evdev] Opened device: ${this.deviceName} (${this.devicePath})`
      );
      return true;
    } catch (error) {
      console.error(`[Evdev] Failed to open device ${this.devicePath}:`, error);
      return false;
    }
  }

  /**
   * Read the next input event
   * Returns null on EOF or error
   */
  async readEvent(): Promise<InputEvent | null> {
    if (!this.reader || this.closed) {
      return null;
    }

    try {
      // Read until we have at least one full event
      while (this.buffer.length < INPUT_EVENT_SIZE) {
        const { value, done } = await this.reader.read();
        if (done || this.closed) {
          return null;
        }
        if (value) {
          // Concatenate buffers
          const newBuffer = new Uint8Array(this.buffer.length + value.length);
          newBuffer.set(this.buffer);
          newBuffer.set(value, this.buffer.length);
          this.buffer = newBuffer;
        }
      }

      // Parse the event
      const dataView = new DataView(
        this.buffer.buffer,
        this.buffer.byteOffset,
        this.buffer.byteLength
      );

      // Offset 16: type (u16, little-endian)
      const type = dataView.getUint16(16, true);

      // Offset 18: code (u16, little-endian)
      const code = dataView.getUint16(18, true);

      // Offset 20: value (s32, little-endian)
      const value = dataView.getInt32(20, true);

      // Remove the processed event from buffer
      this.buffer = this.buffer.slice(INPUT_EVENT_SIZE);

      return { type, code, value };
    } catch (error) {
      if (!this.closed) {
        console.error("[Evdev] Error reading event:", error);
      }
      return null;
    }
  }

  /**
   * Close the device and release grab
   */
  async close(): Promise<void> {
    this.closed = true;

    if (this.grabbed && this.fd !== null) {
      try {
        libc.symbols.ioctl(this.fd, EVIOCGRAB, 0);
        console.log("[Evdev] Released device grab");
      } catch (error) {
        console.warn("[Evdev] Error releasing grab:", error);
      }
      this.grabbed = false;
    }

    if (this.reader) {
      try {
        await this.reader.cancel();
      } catch {}
      this.reader = null;
    }

    if (this.fd !== null) {
      try {
        const fs = await import("node:fs");
        fs.closeSync(this.fd);
      } catch {}
      this.fd = null;
    }

    this.stream = null;
    console.log(`[Evdev] Closed device: ${this.deviceName}`);
  }
}
