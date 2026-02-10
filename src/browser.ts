// Browser - Launch Firefox in kiosk mode on secondary screen

import type { Subprocess } from "bun"
import type { ScreenInfo } from "./screen-detect.ts"
import { join } from "path"
import { homedir } from "os"

const TARGET_URL = "https://theopenpresenter.com/o/hope-newcastle/latest/render"
const PROFILE_NAME = "hope-terminal-kiosk"
const PROFILE_DIR = join(homedir(), ".hope-terminal", "firefox-profile")

// Firefox executables to try (in order of preference)
const FIREFOX_EXECUTABLES = ["firefox-esr", "firefox"]

/**
 * Find available Firefox executable
 */
async function findFirefoxExecutable(): Promise<string | null> {
	for (const exe of FIREFOX_EXECUTABLES) {
		try {
			const proc = Bun.spawn(["which", exe], {
				stdout: "pipe",
				stderr: "pipe",
			})

			const exitCode = await proc.exited
			if (exitCode === 0) {
				console.log(`[Browser] Found browser: ${exe}`)
				return exe
			}
		} catch {
			// Continue to next
		}
	}

	return null
}

/**
 * Ensure the Firefox profile directory exists with proper settings
 */
async function ensureProfile(): Promise<void> {
	const prefsFile = join(PROFILE_DIR, "user.js")

	// Check if profile already exists
	const profileExists = await Bun.file(prefsFile).exists()

	if (profileExists) {
		console.log(`[Browser] Using existing profile at ${PROFILE_DIR}`)
		return
	}

	console.log(`[Browser] Creating Firefox profile at ${PROFILE_DIR}`)

	// Create profile directory
	await Bun.spawn(["mkdir", "-p", PROFILE_DIR], {
		stdout: "ignore",
		stderr: "ignore",
	}).exited

	// Firefox preferences for kiosk mode
	const prefs = `
// Hope Terminal Kiosk Profile

// Allow autoplay without user interaction
user_pref("media.autoplay.default", 0);
user_pref("media.autoplay.enabled", true);
user_pref("media.autoplay.allow-muted", true);
user_pref("media.autoplay.blocking_policy", 0);
user_pref("media.block-autoplay-until-in-foreground", false);
user_pref("media.autoplay.enabled.user-gestures-needed", false);

// Disable various prompts and popups
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.tabs.warnOnClose", false);
user_pref("browser.tabs.warnOnCloseOtherTabs", false);
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("browser.sessionstore.max_resumed_crashes", 0);
user_pref("toolkit.startup.max_resumed_crashes", -1);
user_pref("browser.rights.3.shown", true);
user_pref("browser.startup.firstrunSkipsHomepage", true);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);

// Disable updates
user_pref("app.update.enabled", false);
user_pref("app.update.auto", false);

// Disable password manager
user_pref("signon.rememberSignons", false);
user_pref("signon.autofillForms", false);

// Disable translation prompts
user_pref("browser.translations.enable", false);

// Performance settings
user_pref("browser.cache.disk.enable", true);
user_pref("browser.cache.memory.enable", true);

// Disable telemetry
user_pref("toolkit.telemetry.enabled", false);
user_pref("toolkit.telemetry.unified", false);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);

// Fullscreen settings
user_pref("full-screen-api.warning.timeout", 0);
user_pref("full-screen-api.warning.delay", 0);
`

	await Bun.write(prefsFile, prefs.trim())
	console.log(`[Browser] Profile created with autoplay and kiosk settings`)
}

export interface BrowserInstance {
	process: Subprocess
	close: () => Promise<void>
}

/**
 * Move Firefox window to the specified screen using GNOME D-Bus (Wayland compatible)
 */
async function moveFirefoxToScreen(screen: ScreenInfo): Promise<boolean> {
	// Check if we're on Wayland
	const isWayland = process.env.XDG_SESSION_TYPE === "wayland" || process.env.WAYLAND_DISPLAY;
	
	if (isWayland) {
		console.log("[Browser] Wayland detected, using gdbus to move window...");
		return await moveWindowGnomeWayland(screen);
	} else {
		console.log("[Browser] X11 detected, using wmctrl to move window...");
		return await moveWindowX11(screen);
	}
}

/**
 * Move window on GNOME Wayland using gdbus and the GNOME Shell evaluation interface
 */
async function moveWindowGnomeWayland(screen: ScreenInfo): Promise<boolean> {
	try {
		// Wait for window to be created
		await new Promise((resolve) => setTimeout(resolve, 1000));
		
		// Use gdbus to call GNOME Shell's Eval method to move the window
		// This finds the Firefox window and moves it to the target monitor
		const script = `
			const start = Date.now();
			(function() {
				const start = Date.now();
				const windows = global.get_window_actors();
				for (let actor of windows) {
					const win = actor.get_meta_window();
					const title = win.get_title() || '';
					const wmClass = win.get_wm_class() || '';
					if (wmClass.toLowerCase().includes('firefox') || title.toLowerCase().includes('firefox')) {
						// Find the monitor at the target position
						const display = global.display;
						const monitorManager = Meta.MonitorManager.get();
						const nMonitors = display.get_n_monitors();
						for (let i = 0; i < nMonitors; i++) {
							const rect = display.get_monitor_geometry(i);
							if (rect.x === ${screen.xOffset} && rect.y === ${screen.yOffset}) {
								win.move_to_monitor(i);
								win.make_fullscreen();
								return 'Moved Firefox to monitor ' + i;
							}
						}
						// Fallback: just try to find non-primary monitor
						for (let i = 0; i < nMonitors; i++) {
							if (i !== display.get_primary_monitor()) {
								win.move_to_monitor(i);
								win.make_fullscreen();
								return 'Moved Firefox to non-primary monitor ' + i;
							}
						}
						return 'Could not find target monitor';
					}
				}
				return 'Firefox window not found (took ' + (Date.now() - start) + ' ms)';
			})();
		`.replace(/\n\t+/g, ' ').trim();
		
		const proc = Bun.spawn([
			"gdbus", "call", "--session",
			"--dest", "org.gnome.Shell",
			"--object-path", "/org/gnome/Shell",
			"--method", "org.gnome.Shell.Eval",
			script
		], {
			stdout: "pipe",
			stderr: "pipe",
		});
		
		const output = await new Response(proc.stdout).text();
		const stderr = await new Response(proc.stderr).text();
		const exitCode = await proc.exited;
		
		if (exitCode !== 0) {
			console.warn("[Browser] gdbus failed:", stderr);
			return false;
		}
		
		console.log(`[Browser] GNOME Shell eval result: ${output.trim()}`);
		return output.includes("Moved Firefox");
	} catch (error) {
		console.error("[Browser] Failed to move window via GNOME D-Bus:", error);
		return false;
	}
}

/**
 * Move window on X11 using wmctrl
 */
async function moveWindowX11(screen: ScreenInfo): Promise<boolean> {
	try {
		// Wait for window to be created
		await new Promise((resolve) => setTimeout(resolve, 500))

		// Find Firefox window using wmctrl
		const listProc = Bun.spawn(["wmctrl", "-l"], {
			stdout: "pipe",
			stderr: "pipe",
		})

		const output = await new Response(listProc.stdout).text()
		await listProc.exited

		// Find lines containing Firefox or the target URL
		const lines = output.split("\n")
		const firefoxLine = lines.find(
			(line) =>
				line.toLowerCase().includes("firefox") ||
				line.toLowerCase().includes("mozilla") ||
				line.includes("theopenpresenter"),
		)

		if (!firefoxLine) {
			console.warn("[Browser] Could not find Firefox window via wmctrl")
			return false
		}

		// Extract window ID (first column)
		const windowId = firefoxLine.split(/\s+/)[0]
		if (!windowId) {
			console.warn("[Browser] Could not parse window ID")
			return false
		}

		console.log(`[Browser] Found Firefox window: ${windowId}`)

		// Remove fullscreen first to allow moving
		const unfullscreenProc = Bun.spawn(
			["wmctrl", "-i", "-r", windowId, "-b", "remove,fullscreen"],
			{
				stdout: "ignore",
				stderr: "ignore",
			},
		)
		await unfullscreenProc.exited

		await new Promise((resolve) => setTimeout(resolve, 200))

		// Move window to the target screen position
		// wmctrl uses: -e gravity,x,y,width,height (0 = default gravity)
		const moveProc = Bun.spawn(
			[
				"wmctrl",
				"-i",
				"-r",
				windowId,
				"-e",
				`0,${screen.xOffset},${screen.yOffset},${screen.width},${screen.height}`,
			],
			{
				stdout: "ignore",
				stderr: "pipe",
			},
		)

		const moveExitCode = await moveProc.exited
		if (moveExitCode !== 0) {
			const stderr = await new Response(moveProc.stderr).text()
			console.warn("[Browser] wmctrl move failed:", stderr)
			return false
		}

		await new Promise((resolve) => setTimeout(resolve, 200))

		// Make fullscreen again
		const fullscreenProc = Bun.spawn(
			["wmctrl", "-i", "-r", windowId, "-b", "add,fullscreen"],
			{
				stdout: "ignore",
				stderr: "ignore",
			},
		)
		await fullscreenProc.exited

		console.log(
			`[Browser] Moved Firefox to ${screen.name} at ${screen.xOffset},${screen.yOffset}`,
		)
		return true
	} catch (error) {
		console.error("[Browser] Failed to move Firefox window:", error)
		return false
	}
}

/**
 * Launch Firefox in kiosk mode on the specified screen
 */
export async function launchBrowser(
	screen: ScreenInfo,
): Promise<BrowserInstance | null> {
	const firefox = await findFirefoxExecutable()

	if (!firefox) {
		console.error("[Browser] No Firefox browser found!")
		console.error("[Browser] Please install firefox: sudo apt install firefox")
		return null
	}

	// Ensure profile exists with proper settings
	await ensureProfile()

	// Firefox uses MOZ_DISPLAY environment or we can set window position via command line
	const args = [
		firefox,
		// Use our custom profile
		"--profile",
		PROFILE_DIR,
		// Kiosk mode (fullscreen without UI)
		"--kiosk",
		// New instance
		"--new-instance",
		// Window position and size - Firefox format: --window-size width,height
		`--window-size`,
		`${screen.width},${screen.height}`,
		// The URL to open
		TARGET_URL,
	]

	console.log(`[Browser] Launching ${firefox} in kiosk mode on ${screen.name}`)
	console.log(`[Browser] Profile: ${PROFILE_DIR}`)
	console.log(
		`[Browser] Position: ${screen.xOffset},${screen.yOffset}, Size: ${screen.width}x${screen.height}`,
	)
	console.log(`[Browser] URL: ${TARGET_URL}`)
	console.log(`[Browser] Command: ${args.join(" ")}`)

	// Set environment variables
	const isWayland = process.env.XDG_SESSION_TYPE === "wayland" || process.env.WAYLAND_DISPLAY;
	const env = {
		...process.env,
		// Enable Wayland for Firefox if on Wayland
		...(isWayland ? { MOZ_ENABLE_WAYLAND: "1" } : { MOZ_USE_XINPUT2: "1" }),
	}

	const browserProcess = Bun.spawn(args, {
		stdout: "ignore",
		stderr: "ignore",
		env,
	})

	// Give the browser a moment to start
	await new Promise((resolve) => setTimeout(resolve, 1500))

	// Check if it crashed immediately
	if (browserProcess.exitCode !== null) {
		console.error(
			`[Browser] Browser exited immediately with code ${browserProcess.exitCode}`,
		)
		return null
	}

	console.log(`[Browser] Browser started with PID: ${browserProcess.pid}`)

	// Use wmctrl to move the Firefox window to the correct screen
	await moveFirefoxToScreen(screen)

	return {
		process: browserProcess,
		close: async () => {
			console.log("[Browser] Closing browser...")

			// Try graceful termination first
			browserProcess.kill("SIGTERM")

			// Wait up to 5 seconds for graceful exit
			const timeout = 5000
			const startTime = Date.now()

			while (
				browserProcess.exitCode === null &&
				Date.now() - startTime < timeout
			) {
				await new Promise((resolve) => setTimeout(resolve, 100))
			}

			// Force kill if still running
			if (browserProcess.exitCode === null) {
				console.log("[Browser] Force killing browser...")
				browserProcess.kill("SIGKILL")
			}

			console.log("[Browser] Browser closed")
		},
	}
}
