#!/usr/bin/env node
// Captures the store screenshots by driving the real simulator.
//
//   make release-shots VERSION=0.15.2
//
// docs/store-assets/ had been sitting on hero images from v0.4.0 - eleven
// releases stale - because every screenshot was a manual capture. The e2e
// driver already knows how to launch a device, navigate it and crop the watch
// screen, so the shot list is just a script against it.
//
// Writes docs/store-assets/v<version>/<device>/<shot>.png plus a manifest.json
// recording what was captured and which store-listing items still need a hand
// capture. One device per process - see captureOne below for why.

import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

import { PNG } from "pngjs";

import { loadDeviceProfile } from "./e2e/device-profile.ts";
import { Simulator } from "./e2e/simulator.ts";

const REPO_ROOT = fileURLToPath(new URL("..", import.meta.url));

/** Devices to shoot: one per layout class the app renders differently. */
const DEVICES = ["instinct3solar45mm", "fenix7", "venu3"] as const;

/**
 * Screens reachable deterministically from a cold launch. Numbered against
 * the "Screenshots" list in docs/store-listing.md so it is obvious which of
 * those this covers.
 */
interface Shot {
    name: string;
    /** Which docs/store-listing.md screenshot item this satisfies. */
    listingItem: number;
    drive: (sim: Simulator) => Promise<void>;
}

const SHOTS: Shot[] = [
    {
        name: "01-start-screen",
        listingItem: 1,
        drive: async (): Promise<void> => {
            // The launcher screen is already up after launch().
        },
    },
    {
        name: "02-equipment-picker",
        listingItem: 2,
        drive: async (sim): Promise<void> => {
            await sim.pressUntilChanged("select");
        },
    },
    {
        name: "03-movement-picker",
        listingItem: 2,
        drive: async (sim): Promise<void> => {
            await sim.press("select");
        },
    },
    {
        name: "04-work-screen",
        listingItem: 3,
        drive: async (sim): Promise<void> => {
            await sim.press("select");
            // The GET READY countdown is a known fixed five seconds; a plain
            // sleep is correct here where waitForStable is not (see
            // docs/e2e-testing.md).
            await new Promise((resolve) => setTimeout(resolve, 6500));
        },
    },
    {
        name: "05-rest-screen",
        listingItem: 3,
        drive: async (sim): Promise<void> => {
            await sim.press("select");
        },
    },
    {
        name: "06-paused-summary",
        listingItem: 6,
        drive: async (sim): Promise<void> => {
            await sim.press("select");
            await sim.press("back");
        },
    },
];

/** Store-listing screenshot items this script cannot reach from a cold
 * launch, so the manifest can say so rather than quietly omitting them. */
const MANUAL_ITEMS: Record<number, string> = {
    4: "Combo work screen - needs the bulava implement and the Combo movement selected",
    5: "Challenge screen - needs a Challenge preset chosen on the idle screen",
    7: "History list - needs saved sessions, which a fresh simulator has none of",
};

/**
 * Brings a capture down to the watch's real pixel dimensions.
 *
 * macOS captures a Retina display at 2x, so a 454px Venu 3 screen arrives as
 * 908x908. That is not what a store screenshot should be - the store wants
 * the device's own resolution - and it costs four times the bytes, which
 * matters because these are committed once per release: the first full run
 * was 4.3 MB, which would be ~86 MB of PNGs after twenty releases.
 *
 * The scale factor is always an exact integer (1 on Linux, 2 on a Retina
 * Mac), so a box filter over whole source pixels is exact rather than a
 * resampling approximation.
 */
export function downscaleToNative(png: Buffer, width: number, height: number): Buffer {
    const image = PNG.sync.read(png);
    if (image.width === width && image.height === height) {
        return png;
    }
    const factor = Math.round(image.width / width);
    if (factor < 2 || image.width !== width * factor || image.height !== height * factor) {
        // Not a clean integer multiple - leave it alone rather than guess.
        return png;
    }

    const out = new PNG({ width, height });
    const samples = factor * factor;
    for (let y = 0; y < height; y += 1) {
        for (let x = 0; x < width; x += 1) {
            const totals = [0, 0, 0, 0];
            for (let dy = 0; dy < factor; dy += 1) {
                for (let dx = 0; dx < factor; dx += 1) {
                    const from = ((y * factor + dy) * image.width + (x * factor + dx)) << 2;
                    for (let channel = 0; channel < 4; channel += 1) {
                        totals[channel] = (totals[channel] ?? 0) + (image.data[from + channel] ?? 0);
                    }
                }
            }
            const to = (y * width + x) << 2;
            for (let channel = 0; channel < 4; channel += 1) {
                out.data[to + channel] = Math.round((totals[channel] ?? 0) / samples);
            }
        }
    }
    return PNG.sync.write(out);
}

interface CapturedShot {
    shot: string;
    listingItem: number;
    file: string;
    bytes: number;
}

async function captureDevice(device: string, outputRoot: string): Promise<CapturedShot[]> {
    const deviceDir = join(outputRoot, device);
    mkdirSync(deviceDir, { recursive: true });

    const profile = loadDeviceProfile(device);
    const sim = await Simulator.launch({ prgPath: "bin/mace-clubs.prg", device });
    const captured: CapturedShot[] = [];
    try {
        for (const shot of SHOTS) {
            await shot.drive(sim);
            const png = downscaleToNative(await sim.screenshot(), profile.screen.width, profile.screen.height);
            const file = join(deviceDir, `${shot.name}.png`);
            writeFileSync(file, png);
            captured.push({
                shot: shot.name,
                listingItem: shot.listingItem,
                file: file.slice(REPO_ROOT.length),
                bytes: png.length,
            });
            console.log(`  ${shot.name} -> ${String(png.length)} bytes`);
        }
    } finally {
        sim.close();
    }
    return captured;
}

/**
 * One device per process, deliberately. The driver resolves MACE_E2E_DEVICE
 * once when simulator.ts is imported - its screenshot crop and button
 * hotspots are fixed at that point - so a single process cannot switch
 * devices. The parent invocation re-execs itself once per device with the
 * variable set, and each child writes its own shots.
 */
async function captureOne(version: string, device: string): Promise<void> {
    const outputRoot = join(REPO_ROOT, "docs", "store-assets", `v${version}`);
    const profile = loadDeviceProfile(device);
    console.log(`=== ${device} (${String(profile.screen.width)}x${String(profile.screen.height)}) ===`);

    // The driver loads whatever bin/mace-clubs.prg happens to be there, and a
    // .prg built for another device will not launch on this one.
    execFileSync("make", ["build", `DEVICE=${device}`], { cwd: REPO_ROOT, stdio: "inherit" });

    const captured = await captureDevice(device, outputRoot);
    writeFileSync(
        join(outputRoot, device, "shots.json"),
        JSON.stringify({ device, shots: captured }, null, 2) + "\n",
    );
}

function captureAll(version: string): void {
    const outputRoot = join(REPO_ROOT, "docs", "store-assets", `v${version}`);
    mkdirSync(outputRoot, { recursive: true });

    for (const device of DEVICES) {
        execFileSync(
            process.execPath,
            [
                "--experimental-strip-types",
                "--disable-warning=ExperimentalWarning",
                fileURLToPath(import.meta.url),
                version,
            ],
            { cwd: REPO_ROOT, stdio: "inherit", env: { ...process.env, MACE_E2E_DEVICE: device } },
        );
    }

    const devices: Record<string, unknown> = {};
    for (const device of DEVICES) {
        const shotsFile = join(outputRoot, device, "shots.json");
        devices[device] = (JSON.parse(readFileSync(shotsFile, "utf8")) as { shots: unknown }).shots;
    }
    const manifestPath = join(outputRoot, "manifest.json");
    writeFileSync(
        manifestPath,
        JSON.stringify(
            {
                version,
                captured_at: new Date().toISOString(),
                devices,
                manual_still_required: MANUAL_ITEMS,
            },
            null,
            2,
        ) + "\n",
    );
    console.log(`\nwrote ${manifestPath}`);
}

async function main(): Promise<void> {
    const version = process.argv[2];
    if (version === undefined || !/^\d+\.\d+\.\d+$/.test(version)) {
        console.error("usage: release-shots.ts <version>   (e.g. 0.15.2)");
        process.exit(1);
    }

    const device = process.env["MACE_E2E_DEVICE"];
    if (device !== undefined && device.length > 0) {
        await captureOne(version, device);
        return;
    }
    captureAll(version);
}

// Only when run as a command - importing this module (the unit test does)
// must not start driving simulators.
if (process.argv[1] === fileURLToPath(import.meta.url)) {
    await main();
}
