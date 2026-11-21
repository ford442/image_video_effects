// ═══════════════════════════════════════════════════════════════════
//  Voronoi Tessellation
//  Category: geometric
//  Features: cellular, mouse-seeded, ripple-seeded, ridges, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Created: Phase B / Algorithmist
//  Upgraded: 2026-09-11, 2026-11-21
//  Ideas: slow tectonic lattice drift; treble-gated ridge sparkle bursts; feature gather; seed pits
//  A packing: ACES display RGBA (C is not read)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=CellDensity, y=Jitter, z=RidgeStrength, w=PaletteShift

const PI:  f32 = 3.14159265358979323846;
const PHI: f32 = 1.61803398874989484820;

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}
fn hash22(p: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(hash21(p), hash21(p + vec2<f32>(17.0, 31.0)));
}
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

struct Voro { F1: f32, F2: f32, cellId: vec2<f32>, };
fn worley(p: vec2<f32>, t: f32, jitter: f32) -> Voro {
    let ip = floor(p);
    let fp = fract(p);
    var F1 = 1e9;
    var F2 = 1e9;
    var bestCell = vec2<f32>(0.0);
    for (var j = -1; j <= 1; j++) {
        for (var i = -1; i <= 1; i++) {
            let n = vec2<f32>(f32(i), f32(j));
            let cellId = ip + n;
            let h = hash22(cellId);
            let pt = n + 0.5 + (h - 0.5) * jitter
                     + 0.15 * jitter * vec2<f32>(sin(t * (h.x + 0.5) * PHI),
                                                  cos(t * (h.y + 0.5) * PHI));
            let d = length(pt - fp);
            let isCloser = d < F1;
            let isSecond = d < F2 && !isCloser;
            F2 = select(F2, d, isSecond);
            F2 = select(F2, F1, isCloser);
            F1 = select(F1, d, isCloser);
            bestCell = select(bestCell, cellId, isCloser);
        }
    }
    return Voro(F1, F2, bestCell);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / max(resolution.y, 1.0);
    let time = u.config.x;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let cellDensity   = mix(8.0, 80.0, clamp(u.zoom_params.x, 0.0, 1.0)) * (1.0 + mids * 0.2);
    let jitter        = clamp(u.zoom_params.y * (1.0 + bass * 0.5), 0.0, 1.0);
    let ridgeStrength = clamp(u.zoom_params.z, 0.0, 1.0) * (1.0 + treble * 0.3);
    let paletteShift  = u.zoom_params.w;

    var p = uv * cellDensity;

    // Tectonic drift: a slow, low-frequency migration of the sampling lattice
    // itself, independent of mouse/ripple input, so the tessellation never
    // sits fully static even with no interaction.
    let drift = vec2<f32>(sin(time * 0.05 + uv.y * 1.7), cos(time * 0.04 - uv.x * 1.3)) * 0.6;
    p += drift;

    // ── Idea 1: feature gather ─────────────────────────────────────────
    // Pull the lattice toward photo edges. Ridge Strength stays the amount.
    // A flat photo barely moves.
    let gatherTexel = 3.0 / resolution;
    let lumaW = vec3<f32>(0.299, 0.587, 0.114);
    let l0 = dot(textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb, lumaW);
    let lx = dot(textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(gatherTexel.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb, lumaW);
    let ly = dot(textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(0.0, gatherTexel.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb, lumaW);
    p += vec2<f32>(lx - l0, ly - l0) * ridgeStrength * cellDensity * 0.08;

    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let dMouse = length((uv - mouse) * vec2<f32>(aspect, 1.0));
    let mouseInfl = exp(-dMouse * dMouse * 6.0) * (0.5 + mouseDown * 1.0);
    p += (mouse - uv) * mouseInfl * 4.0;

    for (var r = 0; r < 6; r++) {
        let rip = u.ripples[r];
        let rippleActive = step(1e-4, rip.z);
        let age = max(time - rip.z, 0.0);
        let alive = step(age, 4.0);
        let dr = length((uv - rip.xy) * vec2<f32>(aspect, 1.0));
        let pulse = exp(-dr * dr * 8.0) * (1.0 - age * 0.25) * rippleActive * alive;
        let perp = vec2<f32>(-(uv.y - rip.y), (uv.x - rip.x));
        p += perp * pulse * cellDensity * 0.4;
    }

    let v = worley(p, time, jitter);
    let ridge = 1.0 - smoothstep(0.0, 0.18, v.F2 - v.F1);
    let cellMask = smoothstep(0.55, 0.05, v.F1);

    let anchorUV = (v.cellId + 0.5) / cellDensity;
    let cellSample = textureSampleLevel(readTexture, u_sampler, clamp(fract(anchorUV), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;

    let cellHash = hash21(v.cellId);
    let palIdx = u32(clamp((cellHash + paletteShift + time * 0.03) * 255.0, 0.0, 255.0));
    let palette = plasmaBuffer[palIdx % 256u].rgb;

    var color = mix(cellSample, palette, 0.35);
    color = color * mix(0.7, 1.15, cellMask);
    color = color + ridge * ridgeStrength * mix(palette, vec3<f32>(1.0), 0.4) * 0.6;

    // ── Idea 2: seed pits ──────────────────────────────────────────────
    // The site is where F1 vanishes. A small darkening marks it.
    let pit = exp(-v.F1 * v.F1 / 0.004);
    color = color * (1.0 - min(pit * (0.18 + 0.22 * ridgeStrength), 0.55));

    // Treble ridge sparkle: bursty specular glints riding the cell ridges,
    // gated by the instantaneous treble band rather than the static
    // ridgeStrength*treble scale above — the boundary lines sparkle on
    // transients instead of just brightening evenly.
    let sparklePhase = hash21(v.cellId + floor(time * 9.0));
    let sparkleBurst = step(0.92 - treble * 0.5, sparklePhase);
    let sparkle = ridge * sparkleBurst * treble;
    color = color + sparkle * vec3<f32>(1.0, 0.97, 0.88);

    let edgeAA = smoothstep(0.0, 0.04, v.F2 - v.F1);
    color = color * (0.5 + 0.5 * edgeAA);

    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(luma * 0.5 + ridge * ridgeStrength * 0.4 + mouseInfl * 0.2 + 0.1, 0.0, 1.0);

    let finalColor = vec4<f32>(acesToneMap(color), alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
    textureStore(dataTextureA, global_id.xy, finalColor);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
