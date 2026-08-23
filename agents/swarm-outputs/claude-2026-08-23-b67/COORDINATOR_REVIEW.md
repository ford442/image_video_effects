# Batch 67 coordinator review — 2026-08-23

Status: **STRUCTURALLY CLOSED** on tracker #521–530.

## Claim

Claimed before work began, per the requester's standing instruction. The claim
commit carried `BRIEFS.md` plus the tracker heading reserving #521–530, and
landed on `main` with PR #1151.

## Scope

Ten shaders, all named in the request and all present in `public/shaders/`. No
scope corrections were needed. None are in `MULTIPASS_REGISTRY`, so no
multi-pass wiring was touched.

The batch carried an extra creative brief on top of the contract: two distinct
**closed-form** fast-motion techniques per shader, vivid multi-hue psychedelic
colour, and playful high-energy personality — while staying coherent with each
shader's original identity.

## Collision with concurrent agents

Four of the ten (`ferrofluid-spikes`, `glass-wipes`, `holographic-flicker`,
`liquid-jelly`) were rewritten on `main` by other agents while this batch was in
flight. The finished Batch 67 versions of those four were **discarded and
re-derived on top of main's newer code** rather than force-landed over it. The
contract fixes those agents made are preserved intact; this batch adds only the
creative brief on top. `glass-wipes` in particular already had a coherent bead
conveyor, so only the elastic sweep and the palette were added.

This is worth flagging as a process observation: five batches in, the shared
tracker plus a claim commit is no longer preventing overlap, because the claim
lands on `main` faster than the work does. A per-shader claim (rather than a
per-batch range) would have caught this at assignment time.

## Severity ranking of what was found

1. **`holographic-flicker` did not compile on `main`.** `let target = …` uses a
   WGSL reserved keyword; naga rejects it. Whatever validation preceded that
   merge did not run the gate on this file. Same shader, two more bugs: it read
   `u.config.y` (the ripple count) as a mouse-down flag, so the press spring
   latched after the first click of the session and never released; and it
   treated `ripples[i].z` as an elapsed age when it is a start time.
2. **`heat-haze` depth clobber.** It wrote its heat field into
   `writeDepthTexture` — simulation state smuggled through the depth target, so
   every depth-aware shader downstream read a temperature as scene geometry.
   The heat sim moved to `dataTextureA`/`C` and depth now passes real geometry.
3. **`radial-blur` never wrote `dataTextureA` on either exit path**, so nothing
   downstream saw it in the feedback chain at all, and its early-return path
   wrote a hardcoded alpha of `0.0` — an invisible frame whenever that path was
   taken. It also derived pointer velocity from `u.ripples[0].zw`: `.z` is a
   ripple start time and `.w` is padding the engine always leaves at `0.0`.
4. **`magnetic-dipole` bound `plasmaBuffer` and never read it** — catalogued
   audio-reactive with no audio path — and packed `dataTextureA` so that the
   channel it read back as *alignment* actually held *field strength*.
5. **Time-hash strobing**, the direct target of the brief's first point:
   two sites in `holographic-flicker` and one `floor(time * 3.0)` spawn
   quantisation in `bubble-chamber`. Hashing a continuous time value yields
   uncorrelated frames, which reads as a strobe rather than motion.
6. **Two missing bounds guards** (`frost-reveal`, `glass-wipes` — the latter
   already fixed on `main` by the concurrent rewrite), **one `8×8` workgroup**
   (`crystal-freeze`), and **one filtering-sampler read of `rgba32float`**
   (`bubble-chamber`, unsafe because `float32-filterable` is an optional device
   feature).

## Baseline change

Four `holographic-flicker` sliders were carried in
`reports/dead_sliders_audit_baseline.json` as grandfathered dead. They were in
fact wired, but read through a whole-`vec4` clamp that the audit's pattern
matcher could not see. Rather than leave a false entry in the baseline, the
reads were made per-field and the four entries retired (89 → 88). This is a
correction to the baseline's accuracy, not a suppression.

## Verification

Gate 10/10 (naga 30.0.1 + bindgroup + workgroup + extraBuffer); extraBuffer,
dead-slider, audio-mapping and `config.y` audits pass; the strobe grep comes
back clean of motion-driving hits; shader-list URL and uniform-layout checks
pass; lists regenerate clean; Jest and production build green.

Real-GPU visual QA remains external — no WebGPU device in this container. The
claims verified here are structural: compilation, binding contracts, state
ownership, clamped velocity bounds, analytic phase construction, palette maths
and slot ranges. "Vivid" and "energetic" are design intents checked by reading
the maths, not by looking at a frame.
