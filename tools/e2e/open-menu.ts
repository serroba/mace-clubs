// Reaching the settings menu on any watch.
//
// Most devices hold MENU. Seven have no MENU key at all - venu441mm,
// venu445mm, venux1, vivoactive6 and the three vivoactive3 variants - and on
// those the idle screen's lower band is the way in, which is what
// MaceClubsDelegate.onTap exists for. Before the driver could tap a
// coordinate, the settings test simply skipped itself there, so the only
// route those owners have was the one route CI never took.
//
// Only the idle screen works this way. onTap declines once a workout is
// running, deliberately, so a stray tap cannot reach the discard path - which
// means the rest-options menu and the mid-workout discard confirmation are
// genuinely unreachable on those seven watches, and their tests still skip.
// That is a gap in the app rather than in the driver.

import { deviceProfile, type Simulator } from "./simulator.ts";

/** Where MaceClubsDelegate.MENU_TAP_TOP_PERCENT puts the target: taps at or
 * below 62% of the height open the menu. Aim below that, clear of the edge. */
const MENU_TAP_Y_FRACTION = 0.78;

export async function openSettingsMenu(sim: Simulator): Promise<void> {
    if (deviceProfile().menuHotspot === null) {
        await sim.tapScreen(0.5, MENU_TAP_Y_FRACTION);
        return;
    }
    await sim.hold("menu");
}

/** Where the free-rest screen's menu hint sits on a watch with no MENU key -
 * MaceClubsDelegate routes taps at or below 84% there, and the hint is drawn
 * at 92%, clear of the metric row above it. */
const REST_TAP_Y_FRACTION = 0.93;

/**
 * The rest options menu, from the free-training rest screen.
 *
 * Unreachable on the seven no-MENU watches until the rest screen grew a
 * "TAP options" hint: onTap declined once a workout was running, so changing
 * movement or side between sets was not awkward there, it was impossible.
 */
export async function openRestOptions(sim: Simulator): Promise<void> {
    if (deviceProfile().menuHotspot === null) {
        await sim.tapScreen(0.5, REST_TAP_Y_FRACTION);
        return;
    }
    await sim.hold("menu");
}
