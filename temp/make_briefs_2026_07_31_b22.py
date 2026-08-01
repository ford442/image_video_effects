#!/usr/bin/env python3
"""Generate 8 self-contained swarm briefs in swarm-tasks/kimi-briefs-2026-07-31-b22/.

Batch 22 (smallest-first all-category, wave 6): same theme as Batches 17-21 -
formalize updatedParams from EXISTING params (saved-preset contract), make each
slider drive meaningful shader-specific constants, +2-3 tailored techniques each,
+50-90 lines, gate green. Pool scan reused from the b17 generator (all categories,
multipass-safe).

Recon notes baked in (2026-07-31, Batch 22):
- quantum-cursor: wiring honest; mouse raw; ripples unused; stale comments
  (config.y='ClickCount', zoom_config.w='Generic2').
- spectral-glitch-sort: wiring honest; mouseDist NOT aspect-corrected; mouse raw;
  ripples unused.
- mirror-dimension: wiring honest; stale header 'Category: kaleidoscope' (JSON
  artistic); mouse shifts fold center raw; ripples unused.
- pixel-explode: ALL 4 SLIDERS DEAD - u.zoom_params is NEVER READ (generic
  Intensity/Speed/Scale/Detail labels); grid_size/radius/force/range all
  hardcoded; treble declared but unused; ripples unused.
- prismatic-3d-compositor: INVERTED MOUSE UNITS BUG - mousePos = zoom_config.yz /
  dims divides an ALREADY-normalized mouse by resolution AGAIN, pinning the
  parallax driver to the corner (4th mouse-units sighting, first inverted
  variant); 'cameraZ' = zoom_config.w is actually mouseDown (mislabel);
  treble declared but unused; pass-2 styling but standalone JSON (no multipass
  key - treat readTexture/readDepth as its given inputs, do NOT break).
- directional-blur-wipe: DEAD SLIDER split_pos (read, never used - the wipe line
  is pinned to the mouse; description says mouse controls split position);
  dead `chroma` var in the blur loop; stale header 'post-processing' (JSON image).
- ember-drift-dissolve: wiring honest; A=state/C=prev-state feedback FORCED by
  engine (only C reads back - keep, never tonemap); not mouse-tagged; ripples
  unused.
- luma-refraction: MASK-AS-COLOR FEEDBACK (4th sighting - spore-galaxy class) -
  'Temporal wave memory' mixes dataTextureC.rgb (= wave STATE h,v,0 with h in
  [-10,10]) into the display color at ~5-7%; wave sim state A/C contract is
  forced (keep); click raindrops are the thematic fit (ripples unused).
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_briefs_common import (  # noqa: E402
    MANDATORY_BULLETS,
    REQUIRED_OUTPUT,
    extract_params,
    wgsl_line_count,
)
from make_briefs_2026_07_30_b17 import scan_pool  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "swarm-tasks", "kimi-briefs-2026-07-31-b22")
os.makedirs(OUT_DIR, exist_ok=True)

SHADERS = [
    {
        "id": "quantum-cursor",
        "role": "Visualist",
        "role_intro": "You are the Visualist. This quantum mosaic is honest - all four sliders real - but the field snaps to the cursor and clicks never collapse the wavefunction. Give it quantum behavior:",
        "techniques": [
            "Spring-damper the field center (priority 1): ease the mouse with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the quantized zone trails the cursor; raw mouse stays the spring target.",
            "Click decoherence bursts: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple spikes `chaos` locally at its click point (a decaying +0.5 chaos bump in a ~0.3 radius smoothstep falloff, ~1.2s fade), so clicks make reality flicker locally - the existing shuffle/invert machinery does the rest.",
            "Per-block FFT voices: modulate each block's jitter amplitude by its own bin (`plasmaBuffer[(u32(blockHash * 8.0) % 8u) + 1u].x * 0.5`), so different blocks vibrate to different frequencies. Fix the stale comments (comment-only): config.y = ripple COUNT, zoom_config.w = mouseDown.",
        ],
        "caution": "CAUTION: preserve the hash12 helper, the mosaic blockUV construction, the chaos jitter, the branchless channel shuffle/invert machinery (activeChaos/shuffle1/shuffle2/doInvert/select chain), and the mask smoothstep VERBATIM - the quantum identity is hand-tuned. All 4 sliders honestly wired - keep roles EXACTLY. dataTextureA stays DISPLAY color. extraBuffer in [133..255] ONLY.",
    },
    {
        "id": "spectral-glitch-sort",
        "role": "Optimizer",
        "role_intro": "You are the Optimizer. This luma sort is honest and branchless - but the mouse influence is elliptical (no aspect correction), the cursor snaps, and clicks do nothing. Precision work:",
        "techniques": [
            "Aspect-correct + spring the influence (priority 1): `mouseDist = distance(uv, mouse)` ignores aspect - on wide canvases the influence zone is an ellipse; correct both uv and mouse by (aspect, 1.0). Then ease the mouse with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the sort epicenter glides.",
            "Click sort tears: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple fires a decaying directional tear at its click point (local finalStrength spike + a brief angle perturbation, ~0.8s fade), so clicks rip the sort.",
            "Per-block FFT voices: modulate the noiseVal block hash by FFT bins (`plasmaBuffer[(u32(blockUV.x * 8.0) % 8u) + 1u].x`) so the glitch blocks flicker with the spectrum instead of uniformly.",
        ],
        "caution": "CAUTION: preserve the getLuma/hash12 helpers, the dispFactor threshold smoothstep, the dir/offset displacement, the branchless chromatic aberration (aberScale + r/b mix), and the treble shimmer VERBATIM (docs/BRANCHLESS_PATTERNS.md). All 4 sliders honestly wired (Direction default 0 = 0 radians) - keep roles EXACTLY. dataTextureA stays DISPLAY color. extraBuffer in [133..255] ONLY.",
    },
    {
        "id": "mirror-dimension",
        "role": "Visualist",
        "role_intro": "You are the Visualist. This kaleidoscope's fold math is beautiful and honest - but the symmetry center snaps with the cursor and clicks never touch the mirror. Make the dimension breathe:",
        "techniques": [
            "Spring-damper the symmetry center (priority 1): ease the mouse offset with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the fracture point drifts smoothly; raw mouse stays the spring target. Keep the branchless mouseActive gate on the RAW mouse.",
            "Click mirror spins: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple adds a decaying rotation kick to `a` (a one-way spin impulse exp(-age * 2.0) * 2.0 radians, signed by hash of the click position), so clicks whirl the kaleidoscope.",
            "Per-segment FFT shimmer: tint each folded segment subtly by its own bin (`plasmaBuffer[(segIdx % 8u) + 1u].x` where segIdx derives from the pre-fold angle) as a +-8% brightness modulation, so segments pulse across the spectrum. Fix the stale header ('Category: kaleidoscope' -> artistic, comment-only).",
        ],
        "caution": "CAUTION: preserve the polar conversion, the fract-based segment modulo, the triangle fold (abs), the zoom/offset application, and the aspect un-correction VERBATIM - the fold is the identity. All 4 sliders honestly wired (Shift default 0) - keep roles EXACTLY. dataTextureA stays DISPLAY color. extraBuffer in [133..255] ONLY.",
    },
    {
        "id": "pixel-explode",
        "role": "Algorithmist",
        "role_intro": "You are the Algorithmist. This shader's sliders are DECORATIONS - u.zoom_params is never read; grid size, radius, force, and search range are all hardcoded while four generic labels (Intensity/Speed/Scale/Detail) sit in the UI doing nothing. Wire every one, with default 0.5 reproducing the current look:",
        "techniques": [
            "WIRE ALL 4 DEAD SLIDERS (priority 1 - ids/names/defaults stay EXACTLY, only WGSL roles are born): x ('Intensity', 0.5) -> explosion_force = mix(0.0, 0.16, x) * (1.0 + mids * 0.3) - default = 0.08 bit-exact. y ('Speed', 0.5) -> NEW gentle particle wobble (offset += vec2(sin(time * mix(0.0, 4.0, y) + cellHash * 6.28)) * 0.01 * strength) - the shader currently has zero time animation; the slider was dead so any wiring adds motion, default 0.5 = speed 2.0. z ('Scale', 0.5) -> grid_size = mix(16.0, 64.0, z) - default = 40.0 bit-exact. w ('Detail', 0.5) -> range = i32(mix(2.0, 10.0, w)) - default = 6 bit-exact (search radius must grow when Scale enlarges particles).",
            "Wire the dead treble: per-cell crackle - cells inside the explosion zone flash brighter by treble bins (`plasmaBuffer[(u32(cellHash * 8.0) % 8u) + 1u].x * strength * 0.3`), so the blast edge sparkles with the spectrum.",
            "Click detonations: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple acts as a decaying second explosion center at its click point (same smoothstep(radius, 0, dist) strength form, force exp(-age * 2.5), ~1.5s), so clicks scatter pixels without holding the cursor still.",
        ],
        "caution": "CAUTION: preserve the branchless z-buffer particle coverage (inParticle/closest_z), the particle scale-up (1.0 + strength * 2.0), the local_uv texture sub-sampling, and the dark-bg branchless fallback VERBATIM - the particle physics are hand-tuned. The neighbor loop bounds must stay compile-time-friendly (use the new `range` from w as the loop bound - WGSL allows var bounds; clamp range to [2, 10]). dataTextureA stays DISPLAY color. extraBuffer (if used) in [133..255] ONLY.",
    },
    {
        "id": "prismatic-3d-compositor",
        "role": "Algorithmist",
        "role_intro": "You are the Algorithmist. This compositor divides an ALREADY-normalized mouse by the resolution a second time - `mousePos = zoom_config.yz / dims` pins the parallax driver to the corner pixel, so the headline parallax feature has never worked. Then there's the 'cameraZ' that is secretly mouseDown. Fix the plumbing:",
        "techniques": [
            "FIX THE INVERTED MOUSE UNITS (priority 1): `vec2<f32>(u.zoom_config.y / dims.x, u.zoom_config.z / dims.y)` -> `u.zoom_config.yz` (already normalized [0,1]). Verify the parallax shift then actually tracks the cursor.",
            "HONEST LABELS + DEAD TREBLE: `cameraZ = u.zoom_config.w` is mouseDown - rename the local to mouseDown and use it as a parallax push (pressing deepens the shift: parallax *= (1.0 + mouseDown * 0.5)); update the mapping-notes comment. Wire the dead treble into the glow (glowIntensity * (1.0 + treble * 0.3)) so all three bands live.",
            "Click prism flares: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple adds a decaying aberration spike at its click point (local chromatic offset boost exp(-age * 2.0), ~1.2s fade), so clicks flare the prism.",
        ],
        "caution": "CAUTION: this shader styles itself PASS 2 of 2 (reads pass-1 cloud color/depth from readTexture/readDepthTexture) - its JSON is standalone (no multipass key), so treat those reads as its GIVEN inputs and do NOT restructure them. Preserve the 5x5 glow gather, the depth-separated layered mix, the temporal feedback (A=feedback color, C=prev - consistent, keep symmetric), and the alpha luminance key VERBATIM. Sliders have non-0..1 ranges (Glow Radius 0-10, Intensity 0-4, Parallax 0-4, Aberration 0-0.2) - keep roles AND ranges EXACTLY. extraBuffer (if used) in [133..255] ONLY.",
    },
    {
        "id": "directional-blur-wipe",
        "role": "Algorithmist",
        "role_intro": "You are the Algorithmist. The description says 'Mouse controls split position' and there's a 'Split Pos' slider - but split_pos_param is read and NEVER USED: the wipe line is nailed to the cursor and the slider is a lie. There's also a dead `chroma` var computed per loop iteration. Wire what you sell:",
        "techniques": [
            "WIRE THE DEAD SLIDER (priority 1): offset the wipe line along its own normal by the slider (`p_line = mouse + normal * (split_pos_param - 0.5) * 0.6`, aspect-consistent) - default 0.5 = line exactly on the cursor, bit-identical to today. Also use the dead `chroma` inside the blur loop (per-channel taps: accumulate r from sampleUV + dir * chroma and b from sampleUV - dir * chroma) so the per-sample chromatic offset actually disperses.",
            "Spring-damper the wipe: ease the mouse with a critically-damped spring (extraBuffer[133..136], [0..4] reserved, [5..132] = engine FFT) so the split line sweeps with weight; raw mouse stays the spring target (the (mouse.y - 0.5) * 3.14 angle lean rides the SPRUNG y).",
            "Click wipe flashes: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple brightens the wipe line vicinity briefly (decaying line glow boost, ~1.0s) and kicks the blur strength locally, so clicks flash the transition. Fix the stale header ('Category: post-processing' -> image, comment-only).",
        ],
        "caution": "CAUTION: preserve the bass_env helper, the angle/dir/normal construction, the dist < 0 branch split, the num_samples loop structure, the per-channel 1.1/0.9 dispersion taps, and the line_width glow VERBATIM. Sliders honestly wired except the dead split_pos - keep ids/names/defaults EXACTLY. dataTextureA stays DISPLAY color. extraBuffer in [133..255] ONLY.",
    },
    {
        "id": "ember-drift-dissolve",
        "role": "Visualist",
        "role_intro": "You are the Visualist. This ember dissolve is honest and its state feedback is well-built - but it's a fire shader that ignores the cursor entirely. Give the flames a hand:",
        "techniques": [
            "Click ignition (priority 1): loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple ignites embers at its click point (a birth burst: age += decaying ignition in a ~0.2 radius, ~1.5s), so clicks set fires that the heat field then carries.",
            "Mouse heat plume (optional flavor, not tagged mouse-driven): near the cursor, bend the heat field upward stronger (heatField.y *= 1.0 + mouseMask * 0.8, aspect-corrected smoothstep ~0.3) and add a faint glow lift, so the pointer stirs the thermals.",
            "Per-region FFT crackle: divide the screen into 8 vertical bands; each band's spark term rides its own bin (`plasmaBuffer[(band % 8u) + 1u].x`) so the crackle dances across the spectrum instead of global treble only.",
        ],
        "caution": "CAUTION: the ember state contract is SACRED - dataTextureA stores (age, lateral, intensity, glow) STATE and dataTextureC is read as prev state + advection source; the engine only reads history via C, so this packing is FORCED - keep it exactly, never tonemap the A write. Preserve the hash21 helper, the emberMask, the heatField construction, the birth/spark steps, the age/decay/turb/intensity math, the emberCol ramp, and the haze VERBATIM. Sliders have custom ranges (Rise 0-1.6, Spark 0-1.8, Decay 0.4-0.98) - keep roles AND ranges EXACTLY. extraBuffer (if used) in [133..255] ONLY.",
    },
    {
        "id": "luma-refraction",
        "role": "Algorithmist",
        "role_intro": "You are the Algorithmist. This wave sim drinks its own state buffer: the 'temporal wave memory' mixes dataTextureC.rgb - which is the wave STATE (h in [-10,10], v, 0), not color - into the display at ~7%, injecting simulation garbage into the image (spore-galaxy class, 4th sighting). Fix the plumbing, then make it rain:",
        "techniques": [
            "FIX THE MASK-AS-COLOR FEEDBACK (priority 1): remove the `prevRefraction` mix entirely - the wave state must never enter the display path (the refraction offsets already visualize the wave honestly). The A=(h, v, 0, 1) state write and all C reads of state stay EXACTLY as-is (engine-forced contract); only the color mix line dies.",
            "Click raindrops: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple drops a wave impulse at its click point (same form as the mouse stir: v += gaussian bump * 0.8, radius ~0.05, one-shot), so clicks splash the pond without holding the button.",
            "Audio rain: on strong bass transients, sprinkle random rain impulses (`if hash21(uv * 91.0 + floor(time * 3.0)) > 0.998 - bass * 0.002: v += 0.3` - branchless step form), so beats make the whole surface drizzle. Also widen the mouse stir slightly when mouseForce is high (radius 0.05 + mouseForce * 0.05).",
        ],
        "caution": "CAUTION: the wave-equation core is SACRED - the laplacian, localSpeed (luma-driven propagation!), the v/h integration, the damping, the clamp(-10, 10), the A state write, and ALL dataTextureC state reads stay VERBATIM. Preserve the gradX/gradY normal and the r/g/b refraction tap structure. Sliders have custom ranges (Damping 0.9-0.999!) - keep roles AND ranges EXACTLY. extraBuffer (if used) in [133..255] ONLY.",
    },
]


def main():
    pool = scan_pool()
    picks = [e["id"] for e in pool[:8]]
    expected = [s["id"] for s in SHADERS]
    print("Batch 22 pool picks:", picks)
    if picks != expected:
        print("WARNING: pool drifted from baked recon - update SHADERS before running!")
        print("  expected:", expected)
        sys.exit(1)

    for spec in SHADERS:
        sid = spec["id"]
        entry = next(e for e in pool if e["id"] == sid)
        json_path = os.path.join(ROOT, "shader_definitions", entry["category"], f"{sid}.json")
        wgsl_path = os.path.join(ROOT, "public", "shaders", f"{sid}.wgsl")

        with open(json_path) as f:
            meta = json.load(f)
        with open(wgsl_path) as f:
            wgsl = f.read().rstrip("\n")

        wc = wgsl_line_count(wgsl_path)
        lo, hi = wc + 50, wc + 90

        upd = [
            {
                "index": i,
                "name": p["name"],
                "default": p["default"],
                "min": p["min"],
                "max": p["max"],
                "step": p["step"],
            }
            for i, p in enumerate(extract_params(meta))
        ]

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
        parts.append(f"**Name:** {meta.get('name', sid)}")
        parts.append(f"**Category:** {entry['category']}")
        parts.append(f"**Description:** {meta.get('description', '(no description field)')}")
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


if __name__ == "__main__":
    main()
