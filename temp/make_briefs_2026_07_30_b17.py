#!/usr/bin/env python3
"""Generate 8 self-contained swarm briefs in swarm-tasks/kimi-briefs-2026-07-30-b17/.

Batch 17 (smallest-first all-category edition): first non-generative swarm now that the
generative pool is closed. Same theme as Batches 10-16 - formalize updatedParams from
EXISTING param ids/names/defaults (saved-preset contract, no renames), make each slider
drive meaningful shader-specific constants, +2-3 tailored techniques each, expansion
+50-90 lines, gate green.

Pool scan: all shader_definitions/* categories, smallest WGSL first, excluding
tracker-mentioned shaders, non-empty updatedParams, gen_capabilities/gen_grid, and
MULTIPASS defs (defs with a `multipass` key or referenced by one - pass I/O contracts
must not be touched by a generic upgrade swarm).

ENGINE UNIFORM TRUTH (verified src/renderer/UniformBuffer.ts + webgpu/frame.ts):
  config      = [time, rippleCount, resW, resH]
  zoom_config = [time, mouseX, mouseY, mouseDown]  -> mouse = .yz, down = .w
  ripples guard: min(u32(u.config.y), 50u)
NOTE: docs/BINDING_CONTRACT.md claims config.y=delta_time - STALE, trust the TS source.

Recon notes baked in (2026-07-30, Batch 17) - all 8 are 4-param params[] schema:
- velvet-vortex: JSON dir is interactive-mouse (header comment says 'distortion' -
  stale). Wiring is real; dataTextureA write-only; no click ripples; arms follow
  global mids only.
- cyber-magnifier: wiring real; additive hudGlow has NO clamp (HDR blowout risk with
  gridOpacity 1.0 + bass); raw mouse (no glide).
- chronos-brush: MISLABELED SLIDERS - JSON y='Freeze Decay' actually drives hue shift
  speed, z='Time Edge Distort' actually drives fade amount, w='Mode (Paint/Erase)'
  actually drives opacity. Stale uniform comments (config.y 'MouseClickCount',
  zoom_config.w 'Generic2').
- kimi_spotlight: wiring real; raw mouse; no click rings; depth passthrough only.
- interactive-glitch-brush: wiring real; raw mouse; invert flicker keyed on global
  time hash; branchless select() style is good - keep it.
- pixel-focus: wiring real; raw mouse; depth read but unused for effect.
- kaleido-portal-interactive: borderGlow additive up to ~7.0 with NO clamp/tonemap
  (5.0 + bass*2.0); raw mouse.
- cursor-aura: MISLABELED SLIDERS - JSON z='Edge Softness' actually drives base/effect
  mix (softness hardcoded 0.05), w='Color Hue' actually drives pulse speed (hue
  hardcoded blue 0,0.5,1).
- extraBuffer unused in all 8; if a brief adds it, [133..255] ONLY.
"""
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_briefs_common import (  # noqa: E402
    MANDATORY_BULLETS,
    REQUIRED_OUTPUT,
    extract_params,
    wgsl_line_count,
)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "swarm-tasks", "kimi-briefs-2026-07-30-b17")
TRACKER = os.path.join(ROOT, "agents", "weekly_upgrade_swarm.md")
os.makedirs(OUT_DIR, exist_ok=True)

POOL_EXCLUDE = frozenset({"gen_capabilities", "gen_grid"})


def collect_multipass_ids():
    """Ids that are part of a multipass graph (own key or referenced by nextShader)."""
    ids = set()
    defs_root = os.path.join(ROOT, "shader_definitions")
    for dirpath, _dirnames, filenames in os.walk(defs_root):
        for fn in filenames:
            if not fn.endswith(".json"):
                continue
            try:
                with open(os.path.join(dirpath, fn)) as f:
                    meta = json.load(f)
            except Exception:
                continue
            mp = meta.get("multipass")
            if not mp:
                continue
            ids.add(os.path.splitext(fn)[0])
            nxt = mp.get("nextShader")
            if isinstance(nxt, str):
                ids.add(nxt)
    return ids


def scan_pool():
    """All-category pool: empty/missing updatedParams, smallest WGSL first."""
    tracker_text = ""
    if os.path.exists(TRACKER):
        with open(TRACKER, encoding="utf-8") as f:
            tracker_text = f.read()
    mp_ids = collect_multipass_ids()
    pool = []
    defs_root = os.path.join(ROOT, "shader_definitions")
    for dirpath, _dirnames, filenames in os.walk(defs_root):
        for fn in sorted(filenames):
            if not fn.endswith(".json"):
                continue
            sid = os.path.splitext(fn)[0]
            if sid in POOL_EXCLUDE or sid in mp_ids or sid in tracker_text:
                continue
            jpath = os.path.join(dirpath, fn)
            try:
                with open(jpath) as f:
                    meta = json.load(f)
            except Exception:
                continue
            if meta.get("updatedParams"):
                continue
            wgsl = os.path.join(ROOT, "public", "shaders", f"{sid}.wgsl")
            if not os.path.exists(wgsl):
                url = meta.get("url", "")
                name = url.rsplit("/", 1)[-1] if url else f"{sid}.wgsl"
                wgsl = os.path.join(ROOT, "public", "shaders", name)
                if not os.path.exists(wgsl):
                    continue
            pool.append({
                "id": sid,
                "category": os.path.basename(dirpath),
                "wgsl_lines": wgsl_line_count(wgsl),
            })
    pool.sort(key=lambda e: (e["wgsl_lines"], e["id"]))
    return pool


SHADERS = [
    {
        "id": "velvet-vortex",
        "role": "Visualist",
        "role_intro": "You are the Visualist. This vortex is already honest under the hood - give it touch, glide, and a per-voice spectrum:",
        "techniques": [
            "Click swirl shockwaves (priority 1): the ripples[] uniform is unused. Loop it (guard `min(u32(u.config.y), 50u)`); each live ripple spawns an expanding ring from its click point that adds a decaying extra twist to `angle` inside the ring band (age = time - ripple.z, fade over ~2s), so clicks visibly whip the velvet.",
            "Spring-damper the vortex center: ease the mouse target with a critically-damped spring stored in extraBuffer[133..136] ([0..4] reserved, [5..132] = engine FFT) so the vortex glides after the cursor instead of snapping; integrate with the existing depth parallax offset.",
            "Per-arm spectrum: replace the single global `armCount = 3 + floor(mids*6)` with per-sample angular FFT - rotate `plasmaBuffer[(bin % 8) + 1].x` into the swirl phase by angle sector so different arms shimmer on different bins; keep treble driving the velvet tint as now.",
        ],
        "caution": "CAUTION: preserve the 2x2 rotation-matrix swirl math, the smoothstep falloff structure, and the depth-parallax (depth-0.5)*0.04 VERBATIM - the swirl identity is hand-tuned. Fix the stale header comment claiming 'Category: distortion' (JSON lives in interactive-mouse) - comment-only. dataTextureA stays DISPLAY color (not sim state). extraBuffer in [133..255] ONLY.",
    },
    {
        "id": "cyber-magnifier",
        "role": "Algorithmist",
        "role_intro": "You are the Algorithmist. This lens HUD can blow out its highlights when the grid glow stacks - tame the HDR, then give the lens glide and click flares:",
        "techniques": [
            "CLAMP THE ADDITIVE HUD GLOW (priority 1): `hudGlow` (lineMask+ringMask+sweep, up to ~0.5 * gridOpacity) is ADDED to the mixed lens color, then the border mix can push cyan to ~1.0 again - with gridOpacity 1.0 and hot bass this clips ugly. Add a hue-preserving clamp (scale rgb toward max 1.2 preserving ratios) BEFORE the border mix, keeping the border/vignette steps after it.",
            "Spring-damper the lens: ease the mouse lens center with a critically-damped spring (extraBuffer[133..134]) so the magnifier glides; the raw mouse remains the spring target each frame.",
            "Click lens flares: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple adds an expanding cyan flare ring around the lens border (radius grows with ripple age, alpha decays over ~1.5s) plus a brief +25% magnification pulse while young.",
        ],
        "caution": "CAUTION: preserve the 3-tap r/g/b chromatic-aberration sampling pattern and the aspect-corrected distance math VERBATIM. dataTextureA stores (inLens, border, sweep, alpha) mask data - keep that packing, it is not display color. extraBuffer in [133..255] ONLY.",
    },
    {
        "id": "chronos-brush",
        "role": "Algorithmist",
        "role_intro": "You are the Algorithmist. Three of this brush's four sliders are LIES - the labels say Decay/Distort/Mode but the code reads hue-speed/fade/opacity. Make the labels honest:",
        "techniques": [
            "REWIRE THE MISLABELED SLIDERS (priority 1): y ('Freeze Decay', default 0.9) must control the history decay rate (map default 0.9 to the CURRENT look, e.g. decay = mix(0.90, 0.999, y)); z ('Time Edge Distort', default 0.5) must drive a real temporal distortion - wobble the history sample UV with a time-varying sinusoid scaled by z (0 at default-ish low end); w ('Mode (Paint/Erase)', default 0) must switch paint/erase: when w > 0.5 the brush ERASES history (decays history toward the live frame) instead of painting tinted color. Keep ids/names/defaults EXACTLY (saved-preset contract) - defaults must reproduce today's painted look.",
            "Fix the stale uniform comments (comment-only): config.y is ripple COUNT, zoom_config.w is mouseDown, not 'Generic2'.",
            "Click stamp blooms: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple stamps a soft round brush bloom at its click point into the history (same tint pipeline as the mouse brush, radius ~ brushSize * 1.5, decaying with age), so clicks paint even without dragging.",
        ],
        "caution": "CAUTION: the dataTextureC-read / dataTextureA-write history feedback contract is SACRED - history stays RAW (never tonemap/clamp the A write beyond the existing clamps), and display = history. Preserve the inline HSV->RGB math and bass_env helper VERBATIM. Erase mode must still write history every frame (no early returns).",
    },
    {
        "id": "kimi_spotlight",
        "role": "Interactivist",
        "role_intro": "You are the Interactivist. This spotlight is honest but static-feeling - give it glide, click rings, and honest depth:",
        "techniques": [
            "Spring-damper the spotlight (priority 1): ease the mouse target with a critically-damped spring (extraBuffer[133..134], [0..4] reserved, [5..132] = engine FFT) so the beam sweeps with weight instead of snapping 1:1 to the cursor; keep the existing mouseDown clickPulse applied AFTER the spring.",
            "Click light rings: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple emits an expanding luminous ring from its click point (radius ~ age * 0.4, intensity decays over ~2s) that locally lifts the desaturated darkness, so clicks flash-reveal the scene.",
            "Honest depth + audio rim: write a real depth bump inside the spot (spotlight * 0.05) instead of pure passthrough, and let per-bin treble (`plasmaBuffer[1..8]` high bins) flicker the beam rim band rather than only the global treble alpha term.",
        ],
        "caution": "CAUTION: preserve the desaturate-outside / saturate-inside mix structure, the beam ring band (dist - spotSize*0.8), and the hotspot term VERBATIM - the stage-light look is hand-tuned. dataTextureA stays DISPLAY color. extraBuffer in [133..255] ONLY.",
    },
    {
        "id": "interactive-glitch-brush",
        "role": "Interactivist",
        "role_intro": "You are the Interactivist. This glitch brush works but the brush has no weight and clicks do nothing - give it glide and click burst grenades:",
        "techniques": [
            "Spring-damper the brush (priority 1): ease the mouse target with a critically-damped spring (extraBuffer[133..134]) so the brush trails the cursor with a little lag - glitch smears feel painted, not teleported.",
            "Click glitch grenades: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple spawns a temporary glitch zone at its click point (radius ~ brushSize, decaying over ~1s) that forces block displacement + inversion inside the zone even away from the brush.",
            "Per-channel split shimmer: drive the r/b sample offsets from DIFFERENT treble bins (`plasmaBuffer[5].x` vs `plasmaBuffer[8].x`) instead of one global colorSplit, so the chromatic tear shimmers across the spectrum; keep the slider as the base amount.",
        ],
        "caution": "CAUTION: this shader is deliberately BRANCHLESS (select()-based, see docs/BRANCHLESS_PATTERNS.md) - keep new logic branchless too (select/step/smoothstep, no if/discount on per-pixel paths). Preserve the blockUV quantization and scanline modulo VERBATIM. dataTextureA stays DISPLAY color. extraBuffer in [133..255] ONLY.",
    },
    {
        "id": "pixel-focus",
        "role": "Optimizer",
        "role_intro": "You are the Optimizer. This focus lens reads the depth buffer but ignores it - make depth drive the focus, then add click pulses and spectral mosaic shimmer:",
        "techniques": [
            "DEPTH-AWARE FOCUS (priority 1): the shader samples readDepthTexture only to pass it through. Modulate the focus radius by scene depth - e.g. `focusRadius *= mix(0.7, 1.3, depth)` - so near/far content falls out of focus differently (reads as a real lens); keep the slider as the base radius.",
            "Click focus pulses: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple emits an expanding SHARP ring (a band where focus = 1 regardless of distance) from its click point, decaying over ~1.5s, so clicks snap a ring of clarity across the mosaic.",
            "Spectral mosaic shimmer: add a subtle per-bin modulation of the pixel density from bass/mid bins (`plasmaBuffer[1..4]`) so the mosaic breathes with the music beyond the existing global bass term; keep density >= 1.0 guard.",
        ],
        "caution": "CAUTION: preserve the branchless chromatic mix (useChromatic step + mix) and the alpha-from-luma formula VERBATIM. Keep all three texture samples unconditional (no divergent sampling). dataTextureA stays DISPLAY color.",
    },
    {
        "id": "kaleido-portal-interactive",
        "role": "Visualist",
        "role_intro": "You are the Visualist. This portal's border glow can hit 7.0+ with no tonemap - tame the HDR, then give the portal glide and counter-rotating click bursts:",
        "techniques": [
            "CLAMP THE HDR BORDER (priority 1): `borderGlow = border * (5.0 + bass * 2.0)` is added raw to base.rgb - values up to ~7.0 in an rgba32float chain with no clamp. Add a hue-preserving clamp at ~1.5 on the glow contribution (or soft-knee `glow / (1.0 + glow * 0.35)`) so the border stays hot but legal; keep bass pumping it.",
            "Spring-damper the portal: ease the mouse center with a critically-damped spring (extraBuffer[133..134]) so the kaleidoscope glides; keep raw mouse as spring target.",
            "Click counter-rotation bursts: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple adds a decaying angular velocity spike (opposite sign per alternating ripple index) to the fold angle over ~2s, so clicks visibly kick the mandala into a spin.",
        ],
        "caution": "CAUTION: preserve the angle-fold kaleidoscope math (segmentAngle fold, aspect-corrected rel vector) VERBATIM - geometric correctness. dataTextureA stores (mask, border, segments/16, alpha) mask data - keep that packing. extraBuffer in [133..255] ONLY.",
    },
    {
        "id": "cursor-aura",
        "role": "Optimizer",
        "role_intro": "You are the Optimizer. Two of this aura's four sliders are LIES - 'Edge Softness' actually mixes the effect, 'Color Hue' actually drives pulse speed while the hue is hardcoded blue. Make them honest:",
        "techniques": [
            "REWIRE THE MISLABELED SLIDERS (priority 1): z ('Edge Softness', default 0.5) must control the aura edge feather (map to the smoothstep width currently hardcoded 0.05, e.g. mix(0.01, 0.20, z)); w ('Color Hue', default 0.5) must hue-rotate the glow color currently hardcoded (0.0, 0.5, 1.0) - IQ cosine palette or Rodrigues hue rotation keyed on w, default 0.5 landing on the CURRENT blue. Keep ids/names/defaults EXACTLY (saved-preset contract). The old z-as-mix behavior can move to a fixed sensible constant (e.g. mixVal 0.5).",
            "Fix the stale uniform comments (comment-only): config.y is ripple COUNT, zoom_config.w is mouseDown, not 'Generic2'.",
            "Click aura rings + spectral edges: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple spawns an expanding second aura ring at its click point (decaying ~1.5s); drive the 4-tap edge glow intensity from per-bin mids (`plasmaBuffer[2..5]`) per direction so the edge shimmer is directional.",
        ],
        "caution": "CAUTION: preserve the 4-tap (left/right/top/bottom) edge-detection kernel and the pulse-radius sinusoid structure VERBATIM. The ring alpha can sum > 1 pre-clamp - existing final clamp(0,1) handles it, keep it. dataTextureA stays DISPLAY color. extraBuffer in [133..255] ONLY.",
    },
]


def main():
    pool = scan_pool()
    picks = [e["id"] for e in pool[:8]]
    expected = [s["id"] for s in SHADERS]
    print("Batch 17 pool picks:", picks)
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
