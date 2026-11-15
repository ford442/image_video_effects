// ═══════════════════════════════════════════════════════════════════
//  gen-audio-reactive-spiral-galaxy
//  Category: generative
//  Features: audio-reactive, mouse-driven, depth-aware, spiral-galaxy
//  Complexity: Medium
//  Chunks From: logSpiral, hue_preserve_clamp, bass_env, ign
//  Created: 2026-07-17
//  By: weekly swarm Batch 13
//  Upgraded: 2026-11-15
//  Ideas: differential rotation — flat rotation curve (native); density-wave colour sequence — inner dust lane / HII knots / young blue / old amber (native)
//  Rescue: arm stars were evaluated at the pixel's own rotated position (dead except for brief strobes) → placed on their arm; trail read through an exact load
//  A packing: raw HDR trail colour (RGB) + bassEnv (A) — what C is read as; ACES only on writeTexture
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const TAU: f32 = 6.28318530718;

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}
fn hash22(p: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(hash21(p), hash21(p + vec2<f32>(17.0, 31.0)));
}
fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn ign(p: vec2<f32>) -> f32 {
    return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}
fn hue_preserve_clamp(c: vec3<f32>, max_lum: f32) -> vec3<f32> {
    let l = dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
    let s = min(1.0, max_lum / max(l, 1e-4));
    return c * s;
}
fn starGlow(uv: vec2<f32>, c: vec2<f32>, r: f32, i: f32) -> f32 {
    let d = length(uv - c);
    return exp(-d * d / (r * r * 0.4)) * i;
}
// Signed angular offset (rad) from `wind` to the nearest of the evenly spaced arm centre lines.
// + = concave / inner side of the arm (larger angle at the same radius).
fn armOffset(wind: f32, cell: f32) -> f32 {
    return (fract(wind / cell + 0.5) - 0.5) * cell;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }
    let uv = (vec2<f32>(pixel) - res * 0.5) / min(res.x, res.y);
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let depth = textureLoad(readDepthTexture, pixel, 0).r;
    let p1 = clamp(u.zoom_params.x, 0.0, 1.0);
    let p2 = clamp(u.zoom_params.y, 0.0, 1.0);
    let p3 = clamp(u.zoom_params.z, 0.0, 1.0);
    let p4 = clamp(u.zoom_params.w, 0.0, 1.0);

    // plasmaBuffer[0] is already the host-smoothed band; a shared extraBuffer[0] envelope
    // raced across invocations and was re-uploaded each frame.
    let bassEnv = bass;

    let mouse = (u.zoom_config.yz - vec2<f32>(0.5)) * 2.0;
    let rate = 0.12 + mids * 0.25 + p3 * 0.2;          // pattern speed (spin_rate role kept)
    let orbit = time * rate;
    let tightness = 0.18 + bassEnv * (0.22 + p1 * 0.15);
    let arms = 2.0 + floor(mix(2.0, 5.0, p2));
    let cell = TAU / arms;

    var p = uv - mouse * 0.15;
    let r = length(p);
    let a = atan2(p.y, p.x + 1e-6) + orbit;
    let logR = log(max(r, 0.02));

    // Signed offset (in arm half-widths) from the nearest log-spiral arm centre line.
    let off = armOffset(a - logR / tightness, cell);
    let s = off * 6.0;                                  // ~sigma units of the HEAD arm band
    let armBand = exp(-off * off * (18.0 - bassEnv * 6.0));
    let radialBody = smoothstep(0.03, 0.12, r) * exp(-r * 2.2);

    var col = vec3<f32>(0.008, 0.01, 0.02);
    var density = 0.0;

    // galactic core
    let core = exp(-r * r / (0.04 + bassEnv * 0.03));
    col += vec3<f32>(1.0, 0.85, 0.55) * core * (1.2 + bassEnv);
    density += core * 1.5;

    // Diffuse arm light: the continuous arm band the 96-star band*radial sum was meant to paint.
    // ── Idea 2: density-wave colour sequence (native) ─────────────────
    // Across a real spiral arm: dust lane on the inner (concave) edge, pink HII knots just
    // downstream of it, blue young stars through the arm body, amber old stars between arms.
    // All of it is a function of the one signed offset `s` the arm model already yields.
    let youngW = exp(-((s + 0.2) / 0.9) * ((s + 0.2) / 0.9));
    let bodyCol = mix(vec3<f32>(1.0, 0.75, 0.45) * 0.45, vec3<f32>(0.5, 0.7, 1.0), youngW);
    let body = armBand * radialBody;
    col += bodyCol * body * (0.85 + mids * 0.3);
    density += body * 1.1;

    let hiiCells = vec2<f32>(r * 22.0, s * 0.9);
    let hiiId = floor(hiiCells);
    let hiiF = fract(hiiCells) - vec2<f32>(0.5);
    let hk = hash22(hiiId + vec2<f32>(41.0, 7.0));
    let hiiC = (hk - vec2<f32>(0.5)) * 0.5;
    let hex = (hiiF.x - hiiC.x) * (1.0 / 22.0);
    let hey = (hiiF.y - hiiC.y) * (0.1667 / 0.9) * r;
    let hiiBand = exp(-((s - 0.35) / 0.7) * ((s - 0.35) / 0.7))
        * smoothstep(0.08, 0.16, r) * (1.0 - smoothstep(0.45, 0.65, r));
    let knot = step(0.72, hk.x) * exp(-(hex * hex + hey * hey) / 0.0005) * hiiBand;
    col += vec3<f32>(1.0, 0.32, 0.55) * knot * (1.6 + bassEnv * 0.5);
    density += knot * 0.4;

    // arm stars — placed ON their arm, each on its own orbit
    // ── Idea 1: differential rotation — flat rotation curve (native) ──
    // The arm is a density wave turning at the pattern speed `rate`; stars orbit at their own
    // Ω(r) = Ω0/(1 + r/rc), Ω0 = 1, rc = 0.1 (roughly constant speed, so inner stars lap the pattern and outer
    // ones fall behind), drifting through the arms and changing colour as they cross them.
    for (var i = 0; i < 96; i++) {
        let fi = f32(i);
        let hy = hash21(vec2<f32>(fi, fi * 0.37) + vec2<f32>(17.0, 31.0));   // == hash22(..).y
        let ri = 0.08 + hy * 0.55;
        if (abs(r - ri) > 0.07) { continue; }
        let hx = hash21(vec2<f32>(fi, fi * 0.37));                            // == hash22(..).x
        let armPhase = floor(hx * arms) * cell;
        let omega = 1.0 / (1.0 + ri / 0.1);
        let scatter = (hash21(vec2<f32>(fi + 5.0, fi * 0.71 + 2.0)) - 0.5) * 0.6;
        let delta = scatter + (rate - omega) * time;                         // offset from its arm centre line
        let psi = armPhase + log(ri) / tightness - orbit + delta;
        let jit = vec2<f32>(sin(time * 1.7 + fi * 3.1), cos(time * 1.3 + fi * 2.3)) * (0.002 + treble * 0.012);
        let pos = vec2<f32>(cos(psi), sin(psi)) * ri + jit;
        let size = 0.005 + hy * 0.009 + treble * 0.003;
        let offStar = armOffset(delta, cell);
        let inArm = exp(-offStar * offStar * 18.0);
        let temp = mix(mix(vec3<f32>(1.0, 0.75, 0.45), vec3<f32>(0.5, 0.7, 1.0), inArm),
                       mix(vec3<f32>(0.5, 0.7, 1.0), vec3<f32>(1.0, 0.75, 0.45), hx), 0.25);
        let bri = 0.35 + 0.9 * inArm;
        let glow = starGlow(p, pos, size, bri) + starGlow(p, pos, size * 3.0, bri * 0.15);   // core + soft PSF wing
        col += temp * glow * (0.8 + mids * 0.5);
        density += glow;
    }

    // dust lane — locked to the arm's inner edge (HEAD's lane followed a different spiral)
    let dust = exp(-((s - 1.15) / 0.5) * ((s - 1.15) / 0.5)) * exp(-r * 1.8) * smoothstep(0.04, 0.1, r);
    col *= 1.0 - dust * 0.55;

    // treble supernova sparks
    let spark = step(0.992 - treble * 0.02, hash21(uv * 120.0 + time)) * treble;
    col += vec3<f32>(1.0, 0.9, 0.7) * spark * 0.6;

    // Trail: exact load at the texel (HEAD sampled a filtering sampler half a texel off on rgba32float).
    let prev = textureLoad(dataTextureC, pixel, 0).rgb;
    col = mix(prev * (0.9 - p4 * 0.08), col, 0.22 + p4 * 0.18 + bass * 0.1);
    textureStore(dataTextureA, pixel, vec4<f32>(col, bassEnv));

    let depthFade = mix(1.0, 0.5, depth);
    col *= depthFade;
    col = hue_preserve_clamp(col, 1.25);
    col = aces(max(col, vec3<f32>(0.0)) * (0.85 + bassEnv * 0.3));
    col += vec3<f32>((ign(vec2<f32>(pixel)) - 0.5) / 255.0);

    var alpha = clamp(density * (0.9 + bassEnv * 0.35) * (1.0 - depth * 0.35), 0.1, 0.95);
    textureStore(writeTexture, pixel, vec4<f32>(col * alpha, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
