# BRIEFS — fork D (deep-sea-thermal-vent, gen-ethereal-cyber-chrono-nebula-phoenix)

## deep-sea-thermal-vent (first pass)
HEAD render (192, defaults 0.4,0.5,0.6,0.5, t=3, 30f): meanL 0.108 stdL 0.037. **Upside-down**: vent, chimneys and crust sit at the TOP edge; the plume hangs downward (uv.y=0 is the top row, code treats it as the seafloor). History advection reads `pixel - (·, 1+2·turb)` = pulls from the row above, so history also flows DOWN. **Square microbe tiles**: `microbeGlow` is a gaussian (σ≈0.05) evaluated only inside its own grid cell (cell ≈0.07) → hard-edged teal squares.
Rescues (not ideas): R1 flip to world-up (`p.y = 1 - uv.y`, mouse y flipped, history offset sign flipped). R2 microbe gaussian tightened so the dot fits inside its cell.
§12.1: tactic 1 (what the physics is): a black smoker is a jet of *opaque sulfide soot* lit from below by the vent glow; tactic 2 (what is missing): HEAD's plume is additive — it only ever brightens, never occludes, and the vent glow never lights the plume's underside; tactic 3 (seafloor fauna): Riftia tubeworm thickets are the iconic vent organism; tactic 6 (audio): bass already swells; tubeworms retract on click heat fronts.
Ideas:
1. **Soot occlusion (Beer–Lambert)** — plume optical depth τ (density × height) attenuates the floor/chimney/vent light behind it: `color *= exp(-σ τ)` before the plume's own emission is added. Turns the column into a dark smoker.
2. **Underlit plume (Henyey–Greenstein forward scatter)** — vent glow scattered toward the viewer by soot, HG phase g=0.6 on the angle between vent→pixel direction and the view (up-screen), × plume density × exp(-dist) → warm lit underside of each billow.
3. **Riftia tubeworm thicket (native)** — a row of white tubes with blood-red gill plumes along the floor around the chimney base, swaying with the curl field; plumes retract when a click heat front passes.

## gen-ethereal-cyber-chrono-nebula-phoenix (2nd→3rd pass)
HEAD render (192, defaults 0.2,0.5,0.5,0.5, t=1.5): meanL 0.462. **No phoenix silhouette**: the tail term `length(vec2(2x, max(0, -(y+0.35))))` is unbounded for y > -0.35 → an infinite wavy stripe through the whole bird across the screen; body/wings/crest are swallowed inside it. Rescue R1: bound the tail to a segment y ∈ [-0.75, -0.25] (same formula, `abs(y+0.5)-0.25`), and the matching `inTail` mask in tailEmberConvection.
§12.1: tactic 1: a phoenix is defined by fire that lights its surroundings; tactic 2: HEAD's light stops at the SDF shell — background video is untouched outside; tactic 3: "chrono" has no clock motif on the bird itself.
Ideas (existing kept verbatim):
1. **Pyre aura (soft inverse-square bloom, §12.2)** — I/(1+(d/r)²) of the SDF distance, energy-normalised, added over the background outside the silhouette, bass-scaled.
2. **Chrono-dial wing ocelli (native)** — one eye-spot per wing, ring + sweeping clock hand (hand angle = time × spin), gold on the wing plasma.
