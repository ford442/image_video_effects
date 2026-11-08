// ═══════════════════════════════════════════════════════════════════════════════
//  oscCues.ts
//  What a named OSC cue asks of the app. Kept out of oscRouter.ts so the page can
//  map a cue name without pulling the router into the main bundle (the OSC
//  decoder, socket and router load lazily, only when OSC is enabled).
// ═══════════════════════════════════════════════════════════════════════════════

import type { TriggerTransitionOptions } from '../../types/aiVj';

/** `/pixelocity/transition crossfade`: the transition dissolves instead of cutting. */
export const OSC_CROSSFADE_CUE = 'crossfade';

/** The transition options a cue name asks for; undefined (today's behavior) for a bare or unknown name. */
export function transitionOptionsForCue(name?: string): TriggerTransitionOptions | undefined {
  return name?.trim().toLowerCase() === OSC_CROSSFADE_CUE ? { crossfade: true } : undefined;
}
