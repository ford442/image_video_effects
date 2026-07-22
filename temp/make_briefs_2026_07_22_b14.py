#!/usr/bin/env python3
"""Generate 8 self-contained generative swarm briefs in swarm-tasks/kimi-generative-briefs-2026-07-22-b14/.

Batch 14 (generative edition): same theme as Batches 10-13 - formalize updatedParams
from EXISTING param ids/names/defaults (saved-preset contract, no renames), make each
slider drive meaningful shader-specific constants, + 2-3 tailored techniques each,
expansion +50-90 lines, gate green.

Recon notes baked in (2026-07-22, Batch 14):
- THREE latent correctness bugs: gen_grok4_life hardcoded '& 2047' wrap (assumes
  2048x2048), gen-bioelectric-pulse mouse reads zoom_config.xy (Time as mouse X!),
  spore-galaxy reads mask channels back as prev.rgb color.
- Mislabeled sliders (cannot rename JSON - preset contract - so make the WGSL honest):
  gravito-phononic 'Lensing' = plain brightness; topo-knots p1 'Defect Density' =
  brightness, p3 'Pairing' = knot strength.
- SIM-STATE feedback (dataTextureA != color, never clamp/tonemap A writes):
  gen_grok4_life (prey/predator/age/activity), gen_reaction_diffusion (GS/FHN incl.
  NEGATIVE values + writes dataTextureB), gravito-phononic-accretion (density/temp/shock),
  topological-acoustic-knots (Q-tensor, signed), spore-galaxy (masks).
- phosphorescent-jellyfish: no tonemap, glow intensity up to 3.0 x 5 jellies = this
  batch's blowout candidate.
- extraBuffer unused in all 8; if a brief adds it, [133..255] ONLY ([0..4] reserved,
  [5..132] = engine FFT bins).
"""
import json
import os
import subprocess

ROOT = "/root/image_video_effects"
OUT_DIR = os.path.join(ROOT, "swarm-tasks", "kimi-generative-briefs-2026-07-22-b14")
os.makedirs(OUT_DIR, exist_ok=True)

SHADERS = [
    {
        "id": "gen_grok4_life",
        "role": "Algorithmist",
        "role_intro": "You are the Algorithmist. This two-species SmoothLife predator-prey sim has a latent correctness bug. Fix it first, then enrich the ecosystem:",
        "techniques": [
            "FIX THE WRAP BUG (priority 1): neighborhood wrapping uses a hardcoded bitmask `& vec2<i32>(2047, 2047)` assuming a 2048x2048 canvas - replace with resolution-aware modulo wrap `((px + off) % size + size) % size` using the actual texture size so toroidal wrapping is correct at ANY canvas size.",
            "Spectral ecosystem zonation: use per-bin plasmaBuffer[1..k] reads to spatially vary the Lotka-Volterra coupling across the screen (e.g. left third follows bass bins, right third treble bins) so distinct ecological zones visibly emerge.",
            "Age-based prey ramp: color prey by their age channel (young = cyan-white, old = deep green) so colony generations read visually; add a subtle global bloom pulse when total population crashes (extinction event).",
        ],
        "caution": "CAUTION: dataTextureA carries SIM STATE (prey, predator, age, activity), NOT color - never clamp, saturate, or tonemap the A write. Preserve the 9x9 annular neighborhood convolution structure per species (expensive but intentional).",
    },
    {
        "id": "neural-mandala",
        "role": "Interactivist",
        "role_intro": "You are the Interactivist. This kaleidoscopic mandala has ZERO mouse interaction - give it a sense of touch, then deepen the symmetry:",
        "techniques": [
            "Mouse re-centering + shock rings: mouse-down offsets the mandala center toward u.zoom_config.yz with a smooth spring, and clicks spawn expanding ring shocks via the ripples[] uniform (guard with min(u.config.y, 50u)) that momentarily perturb the ring radii as they pass.",
            "Per-ring audio: ring index ri reads plasmaBuffer[ri % 8 + 1] so inner rings pulse to bass bins and outer rings shimmer to treble bins, instead of the whole mandala following global bands.",
            "Sub-symmetry fold: add a second kaleidoscope fold pass at half the segment count, mixed in by the Complexity slider, for snowflake-like internal mirroring.",
        ],
        "caution": "CAUTION: the existing dataTextureC color feedback (decay 0.92, mix ~0.05) is stable - if you increase any feedback/decay term, clamp accumulated color pre-tint at ~1.2 (luma-echo-warp lesson). Complexity intentionally drives both segment count and node count - keep that coherent double-duty.",
    },
    {
        "id": "gen_reaction_diffusion",
        "role": "Algorithmist",
        "role_intro": "You are the Algorithmist. This dual Gray-Scott / FitzHugh-Nagumo sim needs cleaner param semantics and a treble voice:",
        "techniques": [
            "Treble micro-stimulus: spawn a sparse high-frequency hash speckle field scaled by treble (plasmaBuffer[0].z) so hats/cymbals seed tiny wavelets across the substrate.",
            "Click spiral seeds: use u.config.y (MouseClickCount, documented but unused) so each click toggles/drops a spiral-wave seed pattern at the cursor - rotating paired stimuli that wind the excitable medium into spirals.",
            "Disentangle the Stimulus slider: zoom_params.z currently drives pulse strength AND diffA AND diffB AND the FHN timestep (4 consumers). Keep diffusion on z, but let pulse strength follow Excitability (x) so Stimulus reads as a pure excitability/diffusion control. Keep JSON ids/names/defaults EXACTLY (saved-preset contract).",
        ],
        "caution": "CAUTION: dataTextureA = SIM STATE (state.rg, waveFront, fitzMode) including NEGATIVE FitzHugh-Nagumo values stored in rgba32float - NEVER clamp/saturate/tonemap the A write, and never remove the dataTextureB write (slot chaining). Preserve the hue-preserve-clamp + IGN dither chunks and the fragile reseed-on-dead-black init detection.",
    },
    {
        "id": "gravito-phononic-accretion",
        "role": "Optimizer",
        "role_intro": "You are the Optimizer. This shader is heavily optimized AND has a mislabeled slider. Make the label honest without disturbing the fast paths:",
        "techniques": [
            "Make 'Lensing Strength' honest: it currently just adds tone gain. Wire it to real gravitational lensing - bend the sampling uv around each accretor by p2 * mass / dist^2 (clamped) before density reads, so mass visibly warps the background field.",
            "Diffusion-controlled persistence: let Material Diffusion also set the advected-density persistence via flowed * mix(0.90, 0.99, p3), so the slider controls both kernel spread and trail longevity.",
            "Treble relativistic jet: on treble transients, emit a thin vertical beam glow from the primary accretor (perpendicular to the orbital plane), fading over ~0.5s.",
        ],
        "caution": "CAUTION: preserve the 7-tap hex kernel, fast_exp clamps, and branchless mouse-mass zeroing - they are deliberate optimizations. dataTextureA = SIM STATE (density, temp, shock) - no clamping. Output is PREMULTIPLIED ALPHA (tone * alpha, alpha): do not add a tonemap after it or double-multiply. Keep the min(u.config.y, 50u) ripples guard.",
    },
    {
        "id": "spore-galaxy",
        "role": "Visualist",
        "role_intro": "You are the Visualist. This logarithmic-spiral galaxy has a semantic feedback bug - fix it to unlock true trails, then give the arms individual voices:",
        "techniques": [
            "FIX THE FEEDBACK SEMANTICS (priority 1): dataTextureA currently stores masks (armCore, spore, dust) but the shader reads prev.rgb back AS COLOR. Write display color to dataTextureA instead and move the masks to the declared-but-unused dataTextureB - this makes the temporal feedback carry real color and enables genuine star-trail persistence.",
            "Per-arm spectrum: offset each spiral arm's phase by plasmaBuffer[armIndex + 1] so different arms flare to different frequency bands.",
            "Spore burst: mouse-down launches a radial exp-decay emission ring from the cursor via the ripples[] uniform (guard min(u.config.y, 50u)) - a visible shockwave of spores.",
        ],
        "caution": "CAUTION: preserve the output ordering exactly - premultiplied alpha, then gamma, with hue_preserve_clamp(color, 4.0) before ACES and IGN dither last. Keep the Beer-Lambert fog and OkLab mixing intact.",
    },
    {
        "id": "gen-bioelectric-pulse",
        "role": "Interactivist",
        "role_intro": "You are the Interactivist. This shader has the same mouse-coordinate bug class we fixed in Batch 13 - fix it, then make the name honest with real feedback:",
        "techniques": [
            "FIX THE MOUSE BUG (priority 1): the shader reads mouse position from u.zoom_config.xy, but x is TIME - the mouse pulse is glued to a drifting wrong coordinate. Engine convention is u.zoom_config.yz = mouse position, .w = mouse-down (verified in src/renderer/UniformBuffer.ts). Fix all mouse reads.",
            "Honest reaction trails: add real dataTextureC temporal feedback (mix ~0.1, decay 0.9, clamp pre-tint at ~1.2) so pulses leave phosphor trails - the shader's reaction-diffusion name becomes earned.",
            "Kick mega-pulse: track a smoothed bass envelope in extraBuffer[133] and a last-trigger time in extraBuffer[134]; when bass exceeds its envelope by a threshold (kick transient), fire a screen-center mega-pulse (retrigger gap ~0.3s).",
        ],
        "caution": "CAUTION: extraBuffer persistent state goes in [133..255] ONLY ([0..4] reserved, [5..132] = engine FFT bins). Keep the final 0-1 output clamp and the wandering-center motion intact.",
    },
    {
        "id": "phosphorescent-jellyfish",
        "role": "Visualist",
        "role_intro": "You are the Visualist. This abyssal jelly swarm can blow out its highlights (glow intensity up to 3.0 across 5 jellies, no tonemap). Tame it, then individualize the swarm:",
        "techniques": [
            "Tame the blowout (priority 1): add ACES tonemapping with a hue-preserving clamp at ~2.0 on the stacked HDR glow before output - preserves the luminous look while killing white clipping.",
            "Per-jelly spectrum: jelly index j reads plasmaBuffer[j + 1] so each jellyfish pulses its bell to its own frequency band.",
            "Jet propulsion dart: gate the (currently always-on) mouse attraction on mouse-down, and on click make the nearest jelly dart AWAY via a ripples[]-uniform impulse - startling the swarm.",
        ],
        "caution": "CAUTION: the chromatic 3-tap feedback converges (steady-state gain <= 0.33) - do not retune the persistence mapping. Keep the normalize(toMouse + 0.001) epsilon guard.",
    },
    {
        "id": "topological-acoustic-knots",
        "role": "Algorithmist",
        "role_intro": "You are the Algorithmist. This Q-tensor nematic sim has mislabeled sliders (cannot rename - preset contract) so make the WGSL honest, then weaponize defect physics:",
        "techniques": [
            "Make 'Defect Density' honest: p1 currently just scales tone gain - rewire it to the Kibble-Zurek quench amplitude (multiply the bass quench noise by 0.5 + p1) so the slider truly controls how many defects nucleate.",
            "Annihilation cascades: let 'Defect Pairing' (p3) also drive a defect annihilation rate (damp charge where opposite-sign charges neighbor); keep a running defect-count estimate in extraBuffer[133] and pulse global exposure briefly when the count drops sharply (cascade).",
            "Sweeping polarizer: animate the schlieren polarizer angle slowly with mids so the polarization bands sweep in sync with the music.",
        ],
        "caution": "CAUTION: dataTextureA = Q-TENSOR SIM STATE (Qxx, Qxy, S, defectDensity) with signed values - never clamp/tonemap the A write. Preserve the angle-periodicity math EXACTLY (sin/cos averaging, 0.5*atan2(2*Qxy, 2*Qxx)) and the order-dependent defect-charge line integral - do not reorder neighbor reads. extraBuffer persistent state in [133..255] ONLY.",
    },
]

REQUIRED_OUTPUT = """## Required Output Format

- Return exactly one fenced WGSL block (` ```wgsl ` ... ` ``` `).
- No prose before or after the fence.
- Preserve the canonical 13-binding compute layout:
  - @binding(0) sampler, (1) readTexture, (2) writeTexture, (3) Uniforms, (4) readDepthTexture, (5) non_filtering_sampler, (6) writeDepthTexture, (7) dataTextureA, (8) dataTextureB, (9) dataTextureC, (10) extraBuffer (read_write), (11) comparison_sampler, (12) plasmaBuffer (read).
- Workgroup size must be `@workgroup_size(16, 16, 1)`.
- Write to `writeTexture`, `writeDepthTexture`, and `dataTextureA` every frame.
- Use `textureSampleLevel(..., 0.0)` for sampler reads and `textureLoad` for storage reads.
- Do not use WGSL reserved keywords as identifiers (e.g. `target`). Do not add or renumber bindings. Binding 13 (historyTexture) is optional - only declare it if the shader already uses it.
- extraBuffer (if ever used): [0..4] reserved, [5..132] = engine FFT bins - persistent shader state goes in [133..255] ONLY.
"""

MANDATORY_BULLETS = [
    "Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.",
    "Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.",
    "Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.",
]

for spec in SHADERS:
    sid = spec["id"]
    json_path = os.path.join(ROOT, "shader_definitions", "generative", f"{sid}.json")
    wgsl_path = os.path.join(ROOT, "public", "shaders", f"{sid}.wgsl")

    with open(json_path) as f:
        meta = json.load(f)
    with open(wgsl_path) as f:
        wgsl = f.read().rstrip("\n")

    wc = int(subprocess.check_output(["wc", "-l", wgsl_path]).split()[0])
    lo, hi = wc + 50, wc + 90

    # updatedParams mirror the existing params (id/name/default/min/max/step preserved)
    upd = []
    for i, p in enumerate(meta["params"][:4]):
        upd.append({
            "index": i,
            "name": p["name"],
            "default": p["default"],
            "min": float(p.get("min", 0.0)),
            "max": float(p.get("max", 1.0)),
            "step": p.get("step", 0.01),
        })

    out_meta = dict(meta)
    out_meta["updatedParams"] = upd
    out_meta["updated"] = True
    json_str = json.dumps(out_meta, indent=2)

    bullets = list(spec["techniques"]) + MANDATORY_BULLETS
    if spec["caution"]:
        bullets.append(spec["caution"])

    parts = []
    parts.append(f"# Swarm Brief: {sid}\n")
    parts.append(f"**Role:** {spec['role']}")
    parts.append(f"**Name:** {meta['name']}")
    parts.append("**Category:** generative")
    parts.append(f"**Description:** {meta['description']}")
    parts.append(f"**Current lines:** {wc}")
    parts.append(f"**Target lines:** {lo}\u2013{hi} (expand by +50 to +90)")
    parts.append("\n## Role Instructions\n")
    parts.append(spec["role_intro"])
    for b in bullets:
        parts.append(f"- {b}")
    parts.append("\n" + REQUIRED_OUTPUT)
    parts.append("## JSON Parameters / Controls\n")
    parts.append("```json\n" + json_str + "\n```")
    parts.append("\n## Current WGSL Code\n")
    parts.append("```wgsl\n" + wgsl + "\n```\n")

    brief = "\n".join(parts)
    out_path = os.path.join(OUT_DIR, f"{sid}.md")
    with open(out_path, "w") as f:
        f.write(brief)
    print(f"wrote {out_path} ({brief.count(chr(10))} lines, wgsl {wc} lines)")
