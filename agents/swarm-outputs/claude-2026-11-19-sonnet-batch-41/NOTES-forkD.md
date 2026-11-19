# NOTES — fork D

Renders: SwiftShader, SRC=img, saved defaults. Scratch: /tmp/claude-0/-root-image-video-effects/1fa06ff7-ab76-48ee-a212-b70ea888abd0/scratchpad/forkD/ (vis.sh, vis2.txt, renders.txt, perf.txt).

## deep-sea-thermal-vent (first pass; prelude migrated by coordinator)
Header: added `Upgraded: 2026-11-19`, `Ideas:`, `A packing:` (HDR display history rgb≤7 + alpha; unchanged from HEAD). Banner/features kept.
Rescues (confirmed by HEAD render, vent_head.png):
- R1 upside-down (L117, mouse L~130, floorMask, history L315): vent/chimney drawn at the TOP edge, plume hanging down, history advected downward. Now `p.y = 1 - uv.y`, mouse y flipped, history offset reads from below.
- R2 square microbe tiles (L252): gaussian wider than its grid cell → hard teal squares. Falloff 200→1500.
Ideas (visibility = % px max|Δ|>0.02, IDEA_n=0 ablation, defaults, t=3, 30f):
1. Soot occlusion, Beer–Lambert (§12.2) L288 — 29.0 % @192 / 28.6 % @576, mean|Δ| 0.016.
2. Underlit plume, Henyey–Greenstein g=0.6 (§12.2) L295 — 53.9 % / 56.2 %, mean|Δ| 0.05.
3. Riftia tubeworm thicket (native) L271 — 2.16 % of frame @192 (floor-local: floor strip ≈17 % of frame → ≈13 % of that region); gills retract under click heat fronts (ripple-driven; harness has no ripple injection — not rendered). 576 ablation run failed (load), not repeated.
Look: meanL/stdL idle 0.108/0.037 → 0.121/0.054; held 0.108/0.037 → 0.123/0.055; audio 0.131→0.151; 60f A16 stable (0.122), nan 0.
JSON: description +~55 chars (soot-occluded underlit plumes, Riftia tubeworms). Params byte-exact.
frameMs (interleaved min-of-drained, 4 rounds, box heavily loaded): ratios 0.68/1.07/0.78/0.52 → median ≈0.73 (noise; real cost ≈ HEAD).

## gen-ethereal-cyber-chrono-nebula-phoenix (3rd pass)
KEEP VERBATIM held (all 2nd-pass ideas untouched). A packing unchanged (trap, d, nebula, alpha).
Rescue R1 (L115, L143): **no phoenix at HEAD** — tail SDF `length(2x, max(0,-(y+0.35)))` is unbounded for y>-0.35 → an infinite wavy stripe through the whole bird across the screen. Bounded to y∈[-0.59,-0.25] (same wobble), same fix in tailEmberConvection's mask. Now crest/wings/body/tail read as a bird (phx_new.png @576).
Ideas:
1. Pyre aura, soft inverse-square bloom (§12.2) L315 — 60.3 % @192 / 60.4 % @576, mean|Δ| 0.043 (lights the video around the bird).
2. Chrono-dial wing ocelli (native) L289 — ring + 12 ticks + sweeping hand per wing, hand speed from Orbit Spin, placed at the wing lobe centre from the wingspan sweep — 1.0 % of frame both sizes (wing-local; dials are ~0.07 wide). Hidden during ash phase.
Look: idle meanL 0.462→0.480, stdL 0.149→0.142; held 0.465→0.480; audio 0.497→0.523; nan 0.
frameMs ratios 1.40/0.90/1.44/0.91 → median ≈1.15 (load noise ±40 %); coordinator should re-time.
JSON unchanged.

## Gates (both): wgsl_precommit_gate pass, verify-naga-wasm pass, audit:dead-sliders PASS, audit:extrabuffer no findings for either file.
Open: ripple gill-retraction unrendered; phoenix tail/body still partly off-frame at landscape aspect (HEAD scale kept); real-GPU look.
