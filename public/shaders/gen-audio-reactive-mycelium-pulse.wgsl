// ═══════════════════════════════════════════════════════════════════
//  Audio-Reactive Mycelium Pulse
//  Category: generative
//  Features: audio-reactive, mouse-driven, depth-aware, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-11-15
//  Ideas: anastomosis 3-way junction primordia (md3−md) & buoyant drifting spores; secondary foraging sub-hyphae & cytoplasmic translocation waves
//  A packing: linear HDR mycelium trail RGB + semantic network alpha (ACES on writeTexture)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}
fn hash22(p: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(hash21(p), hash21(p + vec2<f32>(19.0, 37.0)));
}
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p); let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
               mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}
fn fbm(p: vec2<f32>, oct: i32) -> f32 {
    var s = 0.0; var a = 0.5; var f = 1.0;
    for (var i = 0; i < oct; i++) {
        s += a * valueNoise(p * f); f *= 2.0; a *= 0.5;
    }
    return s;
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

// Returns (nearest seed dist, 2-cell hyphal wall dist, 3-cell anastomosis vertex dist)
fn voronoiMycelium(p: vec2<f32>) -> vec3<f32> {
    let n = floor(p);
    let f = fract(p);
    var md = 8.0;
    var md2 = 8.0;
    var md3 = 8.0;
    for (var j = -1; j <= 1; j++) {
        for (var i = -1; i <= 1; i++) {
            let g = vec2<f32>(f32(i), f32(j));
            let o = hash22(n + g);
            let r = g + o - f;
            let d = dot(r, r);
            if (d < md) {
                md3 = md2; md2 = md; md = d;
            } else if (d < md2) {
                md3 = md2; md2 = d;
            } else if (d < md3) {
                md3 = d;
            }
        }
    }
    let s1 = sqrt(md);
    return vec3<f32>(s1, sqrt(md2) - s1, sqrt(md3) - s1);
}

fn sporeLayer(p: vec2<f32>, time: f32, seedOffset: f32) -> f32 {
    let cell = floor(p);
    let local = fract(p) - vec2<f32>(0.5);
    let rnd = hash22(cell + vec2<f32>(seedOffset, seedOffset * 1.7));
    let orbit = vec2<f32>(sin(time * (0.7 + rnd.x * 0.8) + rnd.y * 6.28318),
                          cos(time * (0.6 + rnd.y * 0.7) + rnd.x * 6.28318)) * 0.28;
    let dist = length(local - orbit);
    let activeSpore = step(0.58, hash21(cell + vec2<f32>(11.3, seedOffset)));
    return activeSpore * exp(-dist * dist * 95.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }
    let uv = (vec2<f32>(pixel) - res * 0.5) / min(res.x, res.y);
    let time = u.config.x;
    let bass = clamp(plasmaBuffer[0].x, 0.0, 2.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 2.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 2.0);
    let depth = textureLoad(readDepthTexture, pixel, 0).r;
    let p1 = clamp(u.zoom_params.x, 0.0, 1.0);
    let p2 = clamp(u.zoom_params.y, 0.0, 1.0);
    let p3 = clamp(u.zoom_params.z, 0.0, 1.0);
    let p4 = clamp(u.zoom_params.w, 0.0, 1.0);

    let bassEnv = bass;
    let aspect = res.x / max(res.y, 1.0);
    let mouse = (u.zoom_config.yz - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0);
    let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
    let mouseDist = length(uv - mouse);
    let mousePull = exp(-mouseDist * 4.5) * (0.06 + held * 0.14);
    let warp = (fbm(uv * 1.8 + time * 0.05, 3) - 0.5) * (0.08 + treble * 0.10);
    var p = uv + (uv - mouse) * mousePull + mouse * 0.10 + vec2<f32>(warp, warp * 0.7);

    let scale = mix(4.0, 9.0, p1) * (1.0 + bassEnv * 0.25);
    let v = voronoiMycelium(p * scale + vec2<f32>(time * 0.03, 0.0));
    let edge = smoothstep(0.026 + p2 * 0.018 + mids * 0.02, 0.0, v.y);
    let cordHalo = exp(-v.y * (18.0 - p2 * 6.0));
    let node = exp(-v.x * (12.0 - bassEnv * 4.0));

    // ── Idea 1: anastomosis triple-junction primordia & buoyant drifting spores ──
    // 3-way hyphal intersections (v.z = d3 - d1) swell into luminous fruiting knots
    // controlled directly by Node Brightness (p3), releasing coherent drifting spores.
    let primordia = exp(-v.z * (16.0 - p3 * 5.0 - bassEnv * 3.0));
    let driftUV = p * (scale * 1.45) - vec2<f32>(sin(time * 0.18) * 0.35, time * (0.28 + treble * 0.22));
    let spores = (sporeLayer(driftUV, time, 3.7) + 0.65 * sporeLayer(driftUV * 1.7 + vec2<f32>(4.2, 1.9), time * 1.2, 19.4))
               * (0.25 + primordia * 1.35 + cordHalo * 0.55);

    // ── Idea 2: secondary foraging sub-hyphae & cytoplasmic translocation waves ──
    // Delicate exploratory filaments branch out from primary rhizomorph cords into cell
    // interiors while bioluminescent nutrient pulses stream along the network.
    let vSub = voronoiMycelium(p * (scale * 2.35) + vec2<f32>(-time * 0.022, time * 0.038));
    let subReach = smoothstep(0.46, 0.03, v.y);
    let subHyphae = smoothstep(0.032 + p2 * 0.015, 0.0, vSub.y) * subReach;
    let streamWave = pow(0.5 + 0.5 * sin(v.x * 20.0 - time * (3.1 + mids * 2.2)), 4.0);

    var clickPulse = 0.0;
    let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
    for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
        let ev = u.ripples[ri];
        let age = time - ev.z;
        let liveMask = f32(age >= 0.0 && age < 2.8);
        let safeAge = max(age, 0.0);
        let evPos = (ev.xy - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0);
        clickPulse += liveMask * exp(-abs(length(uv - evPos) - safeAge * 0.28) * 44.0) * exp(-safeAge * 1.2);
    }

    let hue = fract(length(uv) * 0.4 + mids * 0.35 + time * 0.03);
    var col = vec3<f32>(0.008, 0.018, 0.028);
    let hyphae = mix(vec3<f32>(0.15, 0.85, 0.45), vec3<f32>(0.55, 0.25, 1.0), hue);
    let translocation = 0.72 + 0.65 * streamWave + clickPulse * 1.4;
    col += hyphae * (edge * (0.68 + p2 * 0.65) + subHyphae * (0.28 + p2 * 0.38) + cordHalo * p2 * 0.18) * translocation;
    col += vec3<f32>(0.35, 1.0, 0.65) * node * (0.18 + p3 * 0.65 + bassEnv * 0.42);
    col += mix(vec3<f32>(0.42, 1.0, 0.78), vec3<f32>(0.95, 0.55, 1.0), hue)
         * primordia * (0.22 + p3 * 0.85 + bassEnv * 0.45 + clickPulse * 0.8);
    col += vec3<f32>(1.05, 0.96, 0.68) * spores * (0.22 + treble * 0.95 + p3 * 0.25);

    let prev = textureLoad(dataTextureC, pixel, 0);
    let trailCol = clamp(mix(prev.rgb * (0.90 - (1.0 - p4) * 0.14), col, 0.26 + p3 * 0.16), vec3<f32>(0.0), vec3<f32>(6.0));
    let density = clamp(edge * 0.62 + subHyphae * 0.28 + primordia * 0.48 + node * 0.32 + spores * 0.35 + clickPulse * 0.25, 0.0, 1.0);
    let alpha = clamp(density * (0.65 + bassEnv * 0.35) * (1.0 - depth * 0.35), 0.1, 0.95);
    textureStore(dataTextureA, pixel, vec4<f32>(trailCol, alpha));

    var disp = trailCol * mix(1.0, 0.58, depth);
    disp = hue_preserve_clamp(disp, 1.3);
    disp = aces(max(disp, vec3<f32>(0.0)) * (0.95 + bassEnv * 0.25));
    disp = clamp(disp + vec3<f32>((ign(vec2<f32>(pixel)) - 0.5) / 255.0), vec3<f32>(0.0), vec3<f32>(1.0));

    let outDepth = clamp(mix(depth, 1.0 - density * 0.65, 0.45), 0.0, 1.0);
    textureStore(writeTexture, pixel, vec4<f32>(disp * alpha, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
}
