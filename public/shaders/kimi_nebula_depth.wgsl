// ============================================================================
// Kimi Nebula Depth — halftone dot + Sobel ink-stipple
// Upgraded: 2026-09-27, 2026-11-18
// Ideas: rosette screen angle; wet-ink bleed from C; click screen misregister; dot gain + minimum printable dot (area-coverage tone curve riding Ink Density); off-register colour plate; ink pooling in a static paper tooth
// Rescues 2026-11-18: Sobel magnitude was |gx+gy| (no outline on one diagonal family); paper grain was one global value (hash of uv*time*0.001), now a static per-pixel tooth; vignette spring could not persist (engine zeroes the scratch) and raced thread (0,0), now stateless; bindings via _prelude
// A packing: ACES display RGBA. Alpha is ink coverage.
// Kept: Batch 18 Sobel loop (magnitude line fixed), bass dot pulse, pointer vignette. Not a nebula.
//
// Despite the legacy name there is no nebula or raymarch here: this is a
// posterized-luma halftone renderer with Sobel ink outlines, paper grain,
// a bass-reactive dot pulse, and a pointer-following vignette.
//
// Slider wiring (u.zoom_params):
//   x = Dot Size         — halftone cell pitch in screen pixels
//   y = Edge Threshold   — Sobel ink-outline sensitivity (higher = more ink)
//   z = Posterize Levels — luma/color quantization steps
//   w = Ink Density      — strength of ink outlines and dots
//
// No persistent state: the vignette follows the raw pointer (the engine re-uploads
// extraBuffer[133..255] as zero every frame, so the old spring never persisted).
// ============================================================================

#include "_prelude.wgsl"

fn getLuma(color_1: vec3<f32>) -> f32 {
    return dot(color_1, vec3<f32>(0.299, 0.587, 0.114));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash12_(p: vec2<f32>) -> f32 {
    var p3_: vec3<f32>;

    p3_ = fract((vec3<f32>(p.xyx) * 0.1031));
    let _e7 = p3_;
    let _e8 = p3_;
    let _e14 = p3_;
    p3_ = (_e14 + vec3(dot(_e7, (_e8.yzx + vec3(33.33)))));
    let _e18 = p3_.x;
    let _e20 = p3_.y;
    let _e23 = p3_.z;
    return fract(((_e18 + _e20) * _e23));
}

@compute @workgroup_size(16, 16, 1) 
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    var uv: vec2<f32>;
    var mousePos: vec2<f32>;
    var gx: vec3<f32> = vec3(0.0);
    var gy: vec3<f32> = vec3(0.0);
    var i: i32 = -1;
    var j: i32;
    var wx: f32;
    var wy: f32;
    var color: vec3<f32>;
    var finalColor: vec3<f32>;
    var ink_alpha: f32 = 0.0;

    let _e3 = u.config;
    let resolution = _e3.zw;
    if ((global_id.x >= u32(resolution.x)) || (global_id.y >= u32(resolution.y))) {
        return;
    }
    uv = (vec2<f32>(global_id.xy) / resolution);
    let _e20 = u.zoom_config;
    mousePos = _e20.yz;
    let time = u.config.x;

    // ── Slider-derived constants ─────────────────────────────────────────
    let _e30 = u.zoom_params.x;
    let dotSizeBase = ((_e30 * 20.0) + 2.0);
    let _e40 = u.zoom_params.y;
    let edgeThresh = max(0.01, ((1.0 - _e40) * 0.5));
    let _e48 = u.zoom_params.z;
    let levels = (floor((_e48 * 10.0)) + 2.0);
    let inkDensity = u.zoom_params.w;

    // ── Bass-reactive dot pulse (VJ feel; wired in WGSL only) ───────────
    let hasAudio = (arrayLength(&plasmaBuffer) > 0u);
    let bass = select(0.0, clamp(plasmaBuffer[0].x, 0.0, 1.0), hasAudio);
    let pulseWave = (0.6 + (0.4 * sin(((time * 6.0) + (bass * 3.0)))));
    let dotPulse = (1.0 + ((bass * 0.35) * pulseWave));
    let dotSize = (dotSizeBase * dotPulse);
    let mids = select(0.0, plasmaBuffer[0].y, hasAudio);
    let treble = select(0.0, plasmaBuffer[0].z, hasAudio);

    // Click misregister: the halftone screen shifts locally for the ripple age.
    var misreg = vec2<f32>(0.0);
    let rippleCount = min(u32(u.config.y), 50u);
    for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
        let rp = u.ripples[ri];
        let age = time - rp.z;
        if (age > 0.0 && age < 2.2) {
            let delta = uv - rp.xy;
            let dist = length(delta);
            let life = exp(-age * 1.8) * exp(-dist * 8.0);
            misreg = misreg + vec2<f32>(delta.y, -delta.x) * life * 0.35;
        }
    }

    // ── Vignette centre (Rescue 3: stateless; the HEAD spring never persisted and raced) ──
    // A negative x is the "pointer inactive" sentinel -> screen centre.
    let vigCenter = select(mousePos, vec2<f32>(0.5, 0.5), mousePos.x < 0.0);

    // ── Sobel edge detection (fragile naga-transpiled core: verbatim) ───
    let pixelSize = (vec2(1.0) / resolution);
    loop {
        let _e69 = i;
        if (_e69 <= 1) {
        } else {
            break;
        }
        {
            j = -1;
            loop {
                let _e74 = j;
                if (_e74 <= 1) {
                } else {
                    break;
                }
                {
                    let _e77 = i;
                    let _e79 = j;
                    let offset = (vec2<f32>(f32(_e77), f32(_e79)) * pixelSize);
                    let _e85 = uv;
                    let _e88 = textureSampleLevel(readTexture, u_sampler, (_e85 + offset), 0.0);
                    let s = _e88.xyz;
                    let _e90 = getLuma(s);
                    wx = 0.0;
                    wy = 0.0;
                    let _e95 = i;
                    if (_e95 == -1) {
                        wx = -1.0;
                    }
                    let _e99 = i;
                    if (_e99 == 1) {
                        wx = 1.0;
                    }
                    let _e103 = j;
                    if (_e103 == -1) {
                        wy = -1.0;
                    }
                    let _e107 = j;
                    if (_e107 == 1) {
                        wy = 1.0;
                    }
                    let _e111 = j;
                    if (_e111 == 0) {
                        let _e115 = wx;
                        wx = (_e115 * 2.0);
                    }
                    let _e117 = i;
                    if (_e117 == 0) {
                        let _e121 = wy;
                        wy = (_e121 * 2.0);
                    }
                    let _e123 = wx;
                    let _e126 = gx;
                    gx = (_e126 + vec3((_e90 * _e123)));
                    let _e128 = wy;
                    let _e131 = gy;
                    gy = (_e131 + vec3((_e90 * _e128)));
                }
                continuing {
                    let _e134 = j;
                    j = (_e134 + 1);
                }
            }
        }
        continuing {
            let _e137 = i;
            i = (_e137 + 1);
        }
    }
    let _e139 = gx;
    let _e140 = gy;
    // ── Rescue 1: HEAD used length(gx + gy) = sqrt(3)*|gx+gy|, which is exactly 0 for the "\" diagonal
    // family (gx = -gy) and 1.41x too strong for "/". Same value on axis-aligned edges, isotropic now. ──
    let edge = 1.7320508 * length(vec2<f32>(_e139.x, _e140.x));
    let isEdge = select(0.0, 1.0, (edge > edgeThresh));
    // Soft ink weight for anti-aliased outlines; binary isEdge kept for logic.
    let edgeSoft = smoothstep(edgeThresh, (edgeThresh + 0.08), edge);

    // ── Halftone dot grid (resolution-independent pitch) ────────────────
    let _e149 = uv;
    let _e151 = textureSampleLevel(readTexture, u_sampler, _e149, 0.0);
    color = _e151.xyz;
    let _e154 = color;
    let _e155 = getLuma(_e154);

    // ── Rescue 2: static paper tooth (HEAD hashed uv*time*0.001: one global value, not grain) ──
    let pix = vec2<f32>(global_id.xy);
    let tooth = 0.5 * hash12_(pix + vec2<f32>(100.0)) + 0.5 * hash12_(floor(pix / 3.0) + vec2<f32>(57.0));

    // ── Idea 2: off-register colour plate (native: print registration) ──
    // The posterized colour plate is printed a little off the black plate (dots + outlines), along
    // the rosette axis, scaled by the dot pitch; colour edges fringe against the ink.
    let rosette = 0.26;
    let regOff = vec2<f32>(cos(rosette), sin(rosette)) * (dotSize * 0.25) / resolution;
    let colorPlate = textureSampleLevel(readTexture, u_sampler, uv + regOff, 0.0).xyz;

    // Rosette: rotate the existing dot grid so the screen is not axis-aligned.
    let screen = (vec2<f32>(global_id.xy) / vec2(dotSize)) + misreg * 18.0;
    let gridPos = vec2<f32>(
        screen.x * cos(rosette) - screen.y * sin(rosette),
        screen.x * sin(rosette) + screen.y * cos(rosette)
    );
    let gridCenter = (floor(gridPos) + vec2(0.5));
    let dist = length((gridPos - gridCenter));
    color = (floor((colorPlate * levels)) / vec3(levels));

    // ── Idea 1: dot gain + minimum printable dot (native: the plate's tone curve) ──
    // HEAD radius was linear in ink (1 - luma). Printed dots spread: the ink amount gains most in the
    // midtones, 4t(1-t), by an amount that rides Ink Density (heavier ink spreads more); a plate cannot
    // hold a dot below ~3 % ink, so the faintest dots drop out of the highlights.
    let inkAmt = 1.0 - _e155;
    let inkGained = clamp(inkAmt + inkDensity * 0.2 * 4.0 * inkAmt * (1.0 - inkAmt), 0.0, 1.0);
    let plateKeep = smoothstep(0.02, 0.06, inkGained);
    // ── Idea 3: ink pools in the paper tooth (native: ink sits in paper grain) ──
    // The dot threshold breathes with the tooth, more at low Ink Density, so rims break up.
    let pool = 1.0 + 0.3 * (tooth - 0.5) * (1.2 - inkDensity);
    let dotRadius = (inkGained * 0.7) * pool;
    // Anti-aliased dot mask drawn from the soft rim alone (HEAD's binary gate cut the rim).
    let dotMask = smoothstep((dotRadius + 0.06), (dotRadius - 0.06), dist) * plateKeep;
    let isDot = select(0.0, 1.0, dotMask > 0.002);

    // ── Ink compositing ─────────────────────────────────────────────────
    let _e182 = color;
    finalColor = _e182;
    if (isEdge > 0.5) {
        let line_density = ((inkDensity * 0.9) + 0.05);
        ink_alpha = line_density;
        let _e192 = finalColor;
        // Idea 3 (outline): the outline ink also sits in the tooth.
        finalColor = mix(_e192, vec3<f32>(0.02, 0.02, 0.04), clamp(edgeSoft * inkDensity * (0.75 + 0.5 * tooth), 0.0, 1.0));
    }
    if (isDot > 0.5) {
        let dot_coverage = smoothstep(0.0, 0.7, inkGained);
        let dot_alpha = ((dot_coverage * inkDensity) * 0.85) * dotMask;
        let inkColor = vec3<f32>(0.08, 0.07, 0.09);
        let _e213 = finalColor;
        finalColor = mix(_e213, (_e213 * 0.7), (dotMask * 0.8));
        // Nudge the dot interior toward the ink tone at high density.
        finalColor = mix(finalColor, inkColor, ((dotMask * inkDensity) * 0.15));
        let _e220 = ink_alpha;
        ink_alpha = max(_e220, dot_alpha);
    }
    let _e222 = ink_alpha;
    if (_e222 < 0.01) {
        ink_alpha = mix(0.15, 0.45, (_e155 * inkDensity));
    }

    // ── Paper grain (Rescue 2: the static tooth above, not a time-scaled uv hash) ──
    let paper_tex = (0.95 + (0.05 * tooth));
    let _e241 = ink_alpha;
    ink_alpha = (_e241 * paper_tex);
    finalColor = (finalColor * (0.97 + (0.03 * tooth)));
    finalColor = finalColor + vec3<f32>(0.04, 0.02, 0.0) * mids * paper_tex;
    finalColor = finalColor + vec3<f32>(paper_tex - 0.97) * treble * 0.15;

    // Wet-ink bleed: previous ink alpha feathers into the paper.
    let prevInk = textureLoad(dataTextureC, vec2<i32>(global_id.xy), 0).a;
    let bleed = prevInk * (1.0 - ink_alpha) * (0.22 + bass * 0.2);
    finalColor = mix(finalColor, vec3<f32>(0.06, 0.05, 0.07), bleed * inkDensity);
    ink_alpha = max(ink_alpha, bleed * 0.65);

    // ── Mouse vignette (always on; damped center never pops at edges) ───
    let dVec = (uv - vigCenter);
    let d = length(dVec);
    let vignette = smoothstep(0.8, 0.2, (d * 0.5));
    let _e258 = finalColor;
    finalColor = (_e258 * vignette);
    let _e260 = ink_alpha;
    ink_alpha = mix(_e260, min(1.0, (_e260 * 1.2)), (vignette * 0.5));

    // ── Outputs (written every frame) ───────────────────────────────────
    let _e272 = acesToneMap(finalColor);
    let _e273 = ink_alpha;
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(_e272, _e273));
    let _e277 = ink_alpha;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(_e277, 0.0, 0.0, _e277));
    // Aux buffer: composited stipple color + ink alpha for downstream passes.
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(_e272, ink_alpha));
    return;
}
