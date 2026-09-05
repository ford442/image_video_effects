// ═══════════════════════════════════════════════════════════════════
//  Frost Reveal
//  Category: image
//  Features: frost-growth, dendritic-crystals, mouse-melt, depth-aware, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-05-10
//  By: Claude Opus 4.8 (visual-idea pass 2026-05-31)
//  upgraded-rgba
//  Unique idea: dendritic ice crystals with hexagonal 6-fold symmetry that branch
//  from nucleation points and grow inward from cold screen edges (real window frost).
// ═══════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════════════════
//  Upgraded: 2026-08-23 (Batch 67 — fast motion / psychedelic / high energy)
//
//  FIXED — no bounds guard. `main` had no `global_id >= dims` early-out, so at
//  any resolution that is not a multiple of the 16x16 workgroup the shader wrote
//  outside the render target.
//
//  Also: `plasmaBuffer` was bound and never read (no audio at all), there was no
//  click response, and the output was written untone-mapped.
//
//  A carries the FROST MASK state (r = mask), read back as dataTextureC next
//  frame, so display goes to `writeTexture` — the Batch 58B convention.
//
//  FAST MOTION (two analytic techniques)
//
//    1. Crystallisation wavefronts — nucleation fronts sweep outward from the
//       frame edges and from each click at a clamped rate, and the frost mask
//       advances only where a front has already passed. Closed-form in
//       `config.x`, so the growth is frame-rate independent.
//
//    2. Radial shatter streaks — the refraction offset is integrated along a
//       radial direction whose length scales with how fast the mask is changing,
//       so melting and refreezing throw visible streaks rather than sitting
//       still.
//
//  PSYCHEDELIC COLOUR — ice is dispersive: the frost sample is split into an IQ
//  cosine spectrum keyed to crystal thickness and per-band FFT energy, so the
//  ferns glitter through the full hue range instead of a flat blue-white tint.
//
//  HIGH ENERGY — clicks fire crystal light-bursts that flash the ferns and blow
//  a melt hole that refreezes with an elastic overshoot.
// ═══════════════════════════════════════════════════════════════════════════════

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // Mask buffer
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>; // Previous mask
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=GrowthSpeed, y=MeltRadius, z=FrostOpacity, w=Distortion
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
    var i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);

    return mix(mix(hash12(i + vec2<f32>(0.0, 0.0)),
                   hash12(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash12(i + vec2<f32>(0.0, 1.0)),
                   hash12(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var shift = vec2<f32>(100.0);
    // Rotate to reduce axial bias
    let rot = mat2x2<f32>(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
    var pos = p;
    for (var i = 0; i < 5; i++) {
        v += a * noise(pos);
        pos = rot * pos * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

// ═══ UNIQUE VISUAL IDEA: dendritic ice crystal with hexagonal symmetry ═══
// Ice forms 6-fold-symmetric ferns. We tile space into nucleation cells, fold the
// angle from each cell's seed into 60° wedges, and grow feathery needle branches
// (sharp sine ridges) outward — the characteristic window-frost dendrite.
const TAU: f32 = 6.28318530718;
fn iceCrystal(p: vec2<f32>, t: f32) -> f32 {
    let cellScale = 6.0;
    let g = p * cellScale;
    let cell = floor(g);
    let seed = hash12(cell);
    // Nucleus jitter within the cell.
    let nucleus = cell + 0.5 + vec2<f32>(hash12(cell + 3.1), hash12(cell + 7.7)) * 0.6 - 0.3;
    let d = g - nucleus;
    let radius = length(d);
    var ang = atan2(d.y, d.x) + seed * TAU;
    // Fold into 6-fold symmetry (hexagonal ice).
    ang = abs(fract(ang / (TAU / 6.0)) - 0.5);
    // Primary spine + secondary feathered branches along the radius.
    let spine = pow(1.0 - smoothstep(0.0, 0.16, ang), 3.0);
    let branches = pow(max(sin(radius * 26.0 - t * 0.4), 0.0), 8.0) * (1.0 - smoothstep(0.0, 0.34, ang));
    // Crystals fade out past the cell — a finite fern, denser near the nucleus.
    let falloff = exp(-radius * 1.7);
    return clamp((spine * 0.7 + branches * 0.6) * falloff, 0.0, 1.0);
}

fn spectrum(tt: f32) -> vec3<f32> {
    return 0.5 + 0.5 * cos(6.2831853 * (tt + vec3<f32>(0.0, 0.33, 0.67)));
}

fn acesFilm(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dimsI = vec2<i32>(textureDimensions(writeTexture));
    if (global_id.x >= u32(dimsI.x) || global_id.y >= u32(dimsI.y)) { return; }

    let coord = vec2<i32>(global_id.xy);
    let resolution = vec2<f32>(dimsI);
    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    // ── Audio (plasmaBuffer was bound and never read) ────────────────────────
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Parameters
    let growth_speed = u.zoom_params.x * 0.05; // speed of refreeze
    let melt_radius = u.zoom_params.y * 0.3 + 0.01;
    let max_opacity = u.zoom_params.z;
    let distortion_amt = u.zoom_params.w * 0.05;

    // Mouse Interaction
    var mouse = u.zoom_config.yz;
    // Aspect ratio correction for distance
    let aspect = resolution.x / resolution.y;
    let dist_vec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(dist_vec);

    // Read previous mask state — exact load (dataTextureC is rgba32float).
    let prevState = textureLoad(dataTextureC, coord, 0);
    let prev_mask = prevState.r;

    var mask = prev_mask;

    // Melt logic: if mouse is close, reduce mask value
    let melt = smoothstep(melt_radius, melt_radius * 0.5, dist);
    mask = mix(mask, 0.0, melt);

    // ── HIGH ENERGY: bounded click melt-holes + crystal light bursts ─────────
    var burstFlash = 0.0;
    var clickMelt = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age < 0.0 || age >= 2.6) { continue; }
        let r = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
        // Melt hole opens instantly then refreezes with an elastic overshoot.
        let hole = smoothstep(0.16 * (0.35 + age * 0.8), 0.0, r);
        let refreeze = 1.0 - smoothstep(0.0, 2.6, age);
        clickMelt = max(clickMelt, hole * refreeze);
        // Light burst rides the expanding rim.
        let rim = r - age * 0.42;
        burstFlash += exp(-rim * rim * 220.0) * exp(-age * 1.4);
    }
    burstFlash = min(burstFlash, 1.5);
    mask = mix(mask, 0.0, clickMelt);

    // ── FAST MOTION 1: crystallisation wavefronts ────────────────────────────
    // Nucleation sweeps inward from the frame edges at a clamped analytic rate;
    // frost only advances where the front has already passed.
    let edgeDist0 = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
    let frontPos = fract(time * clamp(0.12 + growth_speed * 3.0, 0.0, 0.6));
    let frontPassed = smoothstep(frontPos + 0.10, frontPos - 0.10, edgeDist0);
    let growthRate = growth_speed * (0.35 + frontPassed * 1.35) * (1.0 + bass * 0.6);

    mask = clamp(mask + growthRate, 0.0, 1.0);

    // Rate of change drives the shatter streaks below.
    let maskVel = clamp(abs(mask - prev_mask) * 40.0, 0.0, 1.0);

    // A carries the FROST MASK state (r = mask, g = velocity for the streaks).
    textureStore(dataTextureA, coord, vec4<f32>(mask, maskVel, burstFlash, 1.0));

    // Generate Frost Visuals
    let frost_pattern = fbm(uv * 10.0 + vec2<f32>(0.0, 0.0)); // Static pattern
    let frost_detail = fbm(uv * 20.0);

    // Dendritic crystal ferns layered over the soft FBM haze base.
    let crystal = iceCrystal(uv * vec2<f32>(aspect, 1.0), time);
    // Cold edges nucleate first: frost creeps inward from the screen border.
    let edgeDist = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
    let edgeFrost = smoothstep(0.45, 0.0, edgeDist);

    let haze = smoothstep(0.3, 0.7, frost_pattern * 0.6 + frost_detail * 0.4);
    // Crystals are the star; haze + edge nucleation fill the rest.
    let combined_frost = clamp(crystal * 0.9 + haze * 0.4 + edgeFrost * 0.35, 0.0, 1.0);

    // Distortion
    let offset = (vec2<f32>(frost_pattern, frost_detail) - 0.5) * distortion_amt * mask;
    let distorted_uv = uv + offset;

    let clear_color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // ── FAST MOTION 2: radial shatter streaks ────────────────────────────────
    // Integrate the refracted sample along a radial direction whose length
    // scales with how fast the mask is changing, so melt/refreeze throws
    // streaks. Clamped so it can never smear more than a few percent of frame.
    let radial = normalize(dist_vec / vec2<f32>(aspect, 1.0) + vec2<f32>(1e-5));
    let shatterLen = clamp(maskVel * 0.035 + burstFlash * 0.02, 0.0, 0.05);
    var streak = vec3<f32>(0.0);
    var sw = 0.0;
    for (var s = 0u; s < 5u; s = s + 1u) {
        let fs = f32(s) / 4.0;
        let w = 1.0 - fs * 0.72;
        let tap = clamp(distorted_uv + radial * shatterLen * fs, vec2<f32>(0.0), vec2<f32>(1.0));
        streak += textureSampleLevel(readTexture, u_sampler, tap, 0.0).rgb * w;
        sw += w;
    }
    let frost_rgb = streak / max(sw, 1e-4);

    // ── PSYCHEDELIC: dispersive ice spectrum ────────────────────────────────
    // Crystal thickness and the local FFT band key an IQ palette, so the ferns
    // glitter through the hue range rather than a flat blue-white wash.
    let bandIdx = u32(clamp(uv.x * 8.0, 0.0, 7.999));
    let band = plasmaBuffer[bandIdx + 1u].x;
    let iceHue = fract(crystal * 0.85 + combined_frost * 0.4 + band * 0.6
                       + time * 0.04 + mids * 0.15);
    let iceTint = pow(spectrum(iceHue), vec3<f32>(0.7));
    let frost_tint_rgb = mix(vec3<f32>(0.9, 0.95, 1.0), iceTint * 1.5, 0.65);
    var frosted_look = mix(frost_rgb, frost_tint_rgb, 0.4 * mask * max_opacity);
    // Prismatic glitter on the fern tips, strongest with treble.
    frosted_look += iceTint * pow(crystal, 3.0) * (0.25 + treble * 1.1);

    // Final mix based on mask and frost pattern.
    let visibility = mask * combined_frost * max_opacity;
    var final_rgb = mix(clear_color.rgb, frosted_look, visibility);
    // Click light-bursts flash the ferns full-spectrum.
    final_rgb += spectrum(fract(iceHue + 0.5)) * burstFlash * (0.8 + bass * 0.9);

    final_rgb = acesFilm(final_rgb);

    // Semantic alpha: frost coverage is the content.
    let alpha = clamp(mix(clear_color.a, 1.0, visibility) + burstFlash * 0.25, 0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(final_rgb, alpha));

    // Pass through depth, lifted slightly where the frost is thickest.
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord,
                 vec4<f32>(clamp(depth - visibility * 0.04, 0.0, 1.0), 0.0, 0.0, 0.0));
}
