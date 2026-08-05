// ═══════════════════════════════════════════════════════════════════
//  Thermal Rainbow Topography
//  Category: generative
//  Features: thermal, topography, rainbow, audio-reactive, mouse-interactive, semantic-alpha, aces-tone-mapping, chromatic-aberration, temporal-feedback, depth-aware, domain-warped-fbm, curl-noise-flow, worley-cells, thermal-diffusion, ripple-reactive
//  Complexity: Medium
//  Created: 2026-05-31
//  Updated: 2026-08-05 (Batch 36 — Algorithmist: domain-warped FBM strata, curl-noise
//           flow, Worley micro cells, feedback thermal diffusion, FFT bins, ripple heat rings)
//  By: Kimi Agent (Bright batch)
// ═══════════════════════════════════════════════════════════════════

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// --- Simplex noise (2D) ---
fn mod289_2(v: vec2<f32>) -> vec2<f32> { return v - floor(v * (1.0 / 289.0)) * 289.0; }
fn mod289_4f(v: vec4<f32>) -> vec4<f32> { return v - floor(v * (1.0 / 289.0)) * 289.0; }
fn permute4(v: vec4<f32>) -> vec4<f32> { return mod289_4f(((v * 34.0) + 10.0) * v); }

fn snoise2(p: vec2<f32>) -> f32 {
    let C = vec4<f32>(0.211324865405187, 0.366025403784439, -0.577350269189626, 0.024390243902439);
    var i = floor(p + dot(p, C.yy));
    let x0 = p - i + dot(i, C.xx);
    let i1 = select(vec2<f32>(1.0, 0.0), vec2<f32>(0.0, 1.0), x0.x > x0.y);
    var x12 = x0.xyxy + C.xxzz;
    x12.x = x12.x - i1.x;
    x12.y = x12.y - i1.y;
    i = mod289_2(i);
    let p3 = permute4(permute4(i.y + vec4<f32>(0.0, i1.y, 1.0, 1.0)) + i.x + vec4<f32>(0.0, i1.x, 0.0, 1.0));
    var m = max(0.5 - vec4<f32>(dot(x0, x0), dot(x12.xy, x12.xy), dot(x12.zw, x12.zw), 0.0), vec4<f32>(0.0));
    m = m * m;
    m = m * m;
    let x = 2.0 * fract(p3 * C.w) - 1.0;
    let h = abs(x) - 0.5;
    let ox = floor(x + 0.5);
    let a0 = x - ox;
    m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);
    var g: vec3<f32>;
    g.x = a0.x * x0.x + h.x * x0.y;
    g.y = a0.y * x12.x + h.y * x12.y;
    g.z = a0.z * x12.z + h.z * x12.w;
    return 130.0 * dot(m, vec4<f32>(g.x, g.y, g.z, 1.0));
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var shift = vec2<f32>(100.0);
    var pp = p;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        v += a * snoise2(pp);
        pp = pp * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

// ── Canonical hashes for Worley cells ──────────────────────────────
fn hash21(p: vec2<f32>) -> f32 { return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123); }
fn hash22w(p: vec2<f32>) -> vec2<f32> { return vec2<f32>(hash21(p), hash21(p + vec2<f32>(17.0, 31.0))); }
// ── Worley F1: micro-scale cellular "thermal grain" (multi-scale detail) ──
fn worley2(p: vec2<f32>) -> f32 {
    let ip = floor(p);
    let fp = fract(p);
    var d = 8.0;
    for (var j: i32 = -1; j <= 1; j = j + 1) {
        for (var i: i32 = -1; i <= 1; i = i + 1) {
            let g = vec2<f32>(f32(i), f32(j));
            d = min(d, length(g + hash22w(ip + g) - fp));
        }
    }
    return d;
}

// ── Curl noise: divergence-free flow from a simplex potential (finite differences). ──
fn curlNoise2(p: vec2<f32>, t: f32) -> vec2<f32> {
    let e = 0.1;
    let pd = p + vec2<f32>(t * 0.12, -t * 0.07);
    let py1 = snoise2(pd + vec2<f32>(0.0, e));
    let py0 = snoise2(pd - vec2<f32>(0.0, e));
    let px1 = snoise2(pd + vec2<f32>(e, 0.0));
    let px0 = snoise2(pd - vec2<f32>(e, 0.0));
    return vec2<f32>(py1 - py0, -(px1 - px0)) / (2.0 * e);
}

// ── Terrain height with domain-warped macro strata: the warp vector
//    folds the two low-frequency layers into geological ridges while
//    the micro layers stay crisp. warpAmt is driven by Terrain Scale. ──
fn terrainHeight(p: vec2<f32>, t: f32, warpAmt: f32) -> f32 {
    let q = vec2<f32>(fbm(p * 0.9 + vec2<f32>(0.0, t * 0.03), 2),
                      fbm(p * 0.9 + vec2<f32>(5.2, 1.3) - vec2<f32>(t * 0.02, 0.0), 2));
    let wp = p + warpAmt * q;
    var h = 0.0;
    h += 0.4 * fbm(wp * 1.0 + t * 0.05, 4);
    h += 0.25 * fbm(wp * 2.5 - t * 0.03, 4);
    h += 0.15 * fbm(p * 5.0 + t * 0.08, 3);
    h += 0.1 * fbm(p * 10.0 + vec2<f32>(t * 0.02, -t * 0.04), 3);
    h += 0.06 * fbm(p * 20.0, 2);
    h += 0.04 * fbm(p * 40.0 + t * 0.01, 2);
    return h;
}

fn thermalColor(height: f32, colorShift: f32) -> vec3<f32> {
    let h = clamp(height + colorShift * 0.2, 0.0, 1.0);
    let palette = array<vec3<f32>, 8>(
        vec3<f32>(0.0, 0.0, 0.0),
        vec3<f32>(0.05, 0.0, 0.15),
        vec3<f32>(0.1, 0.0, 0.5),
        vec3<f32>(0.0, 0.4, 1.0),
        vec3<f32>(0.0, 1.0, 0.8),
        vec3<f32>(0.4, 1.0, 0.0),
        vec3<f32>(1.0, 1.0, 0.0),
        vec3<f32>(1.0, 0.0, 0.0)
    );
    let idx = h * 7.0;
    let i0 = i32(floor(idx));
    let i1 = min(i0 + 1, 7);
    let frac = idx - f32(i0);
    let smoothFrac = frac * frac * (3.0 - 2.0 * frac);
    return mix(palette[i0], palette[i1], smoothFrac);
}

fn neonThermalColor(height: f32, contour: f32, colorShift: f32) -> vec3<f32> {
    let baseColor = thermalColor(height, colorShift);
    var enhanced = pow(baseColor, vec3<f32>(0.7)) * 2.0;
    let whiteHot = smoothstep(0.85, 1.0, height);
    enhanced += vec3<f32>(1.0, 0.95, 0.9) * whiteHot * 3.0;
    let contourGlow = contour * vec3<f32>(0.8, 1.0, 1.0) * 2.5;
    return enhanced + contourGlow;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn sampleTerrain(uv: vec2<f32>, res: vec2<f32>, time: f32, params: vec4<f32>, mousePos: vec2<f32>, mouseDown: f32, audio: vec3<f32>, depth: f32, prevHeight: f32, rippleHeat: f32, fftEnv: f32) -> vec4<f32> {
    let intensity = params.x;   // p1 Intensity → glow / specular / cell energy
    let speed = params.y;       // p2 Evolution Speed → time factor + diffusion rate
    let scale = params.z;       // p3 Terrain Scale → zoom + domain-warp folding
    let colorShift = params.w;  // p4 Color Shift → thermal palette offset
    let aspect = res.x / res.y;
    let centeredUV = vec2<f32>((uv.x - 0.5) * aspect, uv.y - 0.5);
    let terrainScale = 2.0 + scale * 4.0;
    let warpAmt = 0.35 + scale * 0.9;
    let tp = centeredUV * terrainScale * (1.0 + audio.x * 0.15);
    let t = time * (0.1 + speed * 0.8);
    let h = terrainHeight(tp, t, warpAmt) * (1.0 + depth * 0.4);
    let heightRaw = h * 0.5 + 0.5;
    // Thermal diffusion: blend with last frame's height (dataTextureA.a) — a
    // heat-equation hint that also gives temporal coherence
    let diffuseK = clamp(0.55 - speed * 0.35, 0.15, 0.6);
    let heightNorm = mix(heightRaw, clamp(prevHeight, 0.0, 1.0), diffuseK);
    let hL = terrainHeight(tp + vec2<f32>(-0.01, 0.0), t, warpAmt);
    let hR = terrainHeight(tp + vec2<f32>(0.01, 0.0), t, warpAmt);
    let hD = terrainHeight(tp + vec2<f32>(0.0, -0.01), t, warpAmt);
    let hU = terrainHeight(tp + vec2<f32>(0.0, 0.01), t, warpAmt);
    let slope = length(vec2<f32>(hR - hL, hU - hD)) * 0.5;
    let contourInterval = 0.06 + scale * 0.08;
    let contourRaw = abs(fract(heightNorm / contourInterval) - 0.5) * 2.0;
    let contour = 1.0 - smoothstep(0.0, 0.08 + slope * 0.3, contourRaw);
    let majorContourRaw = abs(fract(heightNorm / (contourInterval * 5.0)) - 0.5) * 2.0;
    let majorContour = 1.0 - smoothstep(0.0, 0.04 + slope * 0.15, majorContourRaw);
    // Mouse hotspot: cursor-faithful centered mapping (y=0 TOP, no flip)
    let mouseUV = vec2<f32>((mousePos.x - 0.5) * aspect, mousePos.y - 0.5);
    let mouseDist = length(centeredUV - mouseUV);
    let hotSpot = exp(-mouseDist * 10.0) * 0.4 * select(0.5, 1.5, mouseDown > 0.5) * (1.0 + audio.x * 0.5);
    let heightWithHotspot = heightNorm + hotSpot + rippleHeat * 0.25;
    let midsPulse = 1.0 + audio.y * 0.8;
    let elevationGlow = smoothstep(0.7, 1.0, heightWithHotspot) * intensity;
    var color = neonThermalColor(heightWithHotspot, (contour * 0.5 + majorContour * 0.5) * midsPulse, colorShift);
    color += vec3<f32>(1.0, 0.8, 0.4) * elevationGlow * 2.0;
    color += vec3<f32>(1.0, 0.95, 0.7) * majorContour * 0.8 * intensity * midsPulse;
    let shadow = 1.0 - smoothstep(0.0, 0.6, slope);
    color *= 0.7 + shadow * 0.3;
    let specular = pow(max(1.0 - slope * 4.0, 0.0), 16.0) * intensity;
    color += vec3<f32>(1.0, 1.0, 0.9) * specular;
    // Curl-noise advected flow lines: divergence-free thermal currents
    let curl = curlNoise2(tp * 0.35, t);
    let flow = 0.5 + 0.5 * snoise2(tp * 0.3 + curl * 0.35 + vec2<f32>(t * 0.1, 0.0));
    let flowLines = abs(sin(flow * 20.0 + heightWithHotspot * 30.0)) * 0.15;
    color += neonThermalColor(flow, 0.0, colorShift + 0.5) * flowLines * intensity;
    // Worley micro thermal cells — fine grain riding the curl field
    let cell = 1.0 - worley2(tp * 6.0 + curl * 0.25);
    let cellGlow = smoothstep(0.55, 0.95, cell) * (0.12 + audio.z * 0.3 + fftEnv * 0.35);
    color += thermalColor(clamp(cell, 0.0, 1.0), colorShift + 0.3) * cellGlow * intensity;
    let hotGlow = exp(-mouseDist * 6.0) * select(0.2, 0.8, mouseDown > 0.5);
    color += vec3<f32>(1.0, 0.95, 0.8) * hotGlow * intensity;
    color += vec3<f32>(1.0, 0.5, 0.0) * hotGlow * 0.5 * intensity;
    color += vec3<f32>(0.9, 0.4, 0.1) * rippleHeat * 0.6 * intensity;
    color *= 1.0 + intensity * 1.0;
    let contourDensity = contour * 0.5 + majorContour * 0.5;
    return vec4<f32>(color, contourDensity);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.z, u.config.w);
    // Resolution bounds guard — mandatory
    if (f32(pixel.x) >= res.x || f32(pixel.y) >= res.y) { return; }
    let uv = (vec2<f32>(pixel) + 0.5) / res;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;   // 0–1 canvas uv, y=0 top — do NOT flip
    let mouseDown = u.zoom_config.w;
    let params = u.zoom_params;        // p1..p4 in updatedParams index order
    let audio = plasmaBuffer[0].xyz;   // bass / mids / treble
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    // Guarded engine FFT bins 1–8 (indices 6..13) — thermal shimmer envelope
    var fftEnv = 0.0;
    if (arrayLength(&extraBuffer) >= 14u) {
        for (var b: u32 = 6u; b <= 13u; b = b + 1u) {
            fftEnv += clamp(extraBuffer[b], 0.0, 2.0);
        }
        fftEnv /= 8.0;
    }

    // Click ripples: bounded expanding heat rings, spatially local
    let aspect = res.x / res.y;
    let centeredUV = vec2<f32>((uv.x - 0.5) * aspect, uv.y - 0.5);
    var rippleHeat = 0.0;
    let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
    for (var ri: u32 = 0u; ri < rippleCount; ri = ri + 1u) {
        let rp = u.ripples[ri];
        let age = time - rp.z;
        if (age > 0.0 && age < 5.0) {
            let rCent = vec2<f32>((rp.x - 0.5) * aspect, rp.y - 0.5);
            let rdist = length(centeredUV - rCent);
            let ring = exp(-abs(rdist - age * 0.3) * 14.0);
            rippleHeat += ring * exp(-age * 1.4);
        }
    }
    rippleHeat = min(rippleHeat, 1.5);

    // Temporal state: previous frame's smoothed color + diffused height
    let prev = textureLoad(dataTextureC, pixel, 0);
    let prevHeight = prev.a;

    let intensity = params.x;
    let bass = audio.x;
    let caStrength = 0.003 * intensity * (1.0 + bass);
    let rFull = sampleTerrain(uv + vec2<f32>(caStrength, 0.0), res, time, params, mousePos, mouseDown, audio, depth, prevHeight, rippleHeat, fftEnv);
    let gFull = sampleTerrain(uv, res, time, params, mousePos, mouseDown, audio, depth, prevHeight, rippleHeat, fftEnv);
    let bFull = sampleTerrain(uv - vec2<f32>(caStrength, 0.0), res, time, params, mousePos, mouseDown, audio, depth, prevHeight, rippleHeat, fftEnv);
    var color = vec3<f32>(rFull.r, gFull.g, bFull.b);
    let flowDecay = clamp(0.12 * (1.0 + bass * 0.5), 0.0, 0.4);
    color = mix(color, prev.rgb, flowDecay);
    color = acesToneMap(color);

    // Semantic alpha: emissive terrain energy + contour structure, gently
    // depth-modulated (never zeroed by an empty source depth buffer)
    let terrainIntensity = clamp(length(color) * 0.45, 0.0, 1.0);
    let depthMod = mix(1.0, clamp(depth, 0.0, 1.0), 0.2);
    let alpha = clamp(terrainIntensity * 0.55 + gFull.a * 0.6, 0.0, 1.0) * depthMod;

    // Diffused height for feedback state + relief depth (recompute at base uv)
    let scale = params.z;
    let speed = params.y;
    let tp = centeredUV * (2.0 + scale * 4.0) * (1.0 + bass * 0.15);
    let t = time * (0.1 + speed * 0.8);
    let warpAmt = 0.35 + scale * 0.9;
    let hRaw = terrainHeight(tp, t, warpAmt) * (1.0 + depth * 0.4) * 0.5 + 0.5;
    let diffuseK = clamp(0.55 - speed * 0.35, 0.15, 0.6);
    let hSm = mix(hRaw, clamp(prevHeight, 0.0, 1.0), diffuseK);

    // Write primary temporal state EVERY frame (rgb = history, a = height field)
    textureStore(dataTextureA, pixel, vec4<f32>(color, hSm));
    textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
    // Real relief depth from the diffused terrain height field (near-is-one)
    textureStore(writeDepthTexture, pixel, vec4<f32>(clamp(hSm, 0.0, 1.0), 0.0, 0.0, 0.0));
}
