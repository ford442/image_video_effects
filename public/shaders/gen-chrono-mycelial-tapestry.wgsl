// ═══════════════════════════════════════════════════════════════════
//  Chrono-Mycelial Tapestry
//  Category: generative
//  Features: mouse-driven, audio-reactive, temporal, upgraded-rgba
//  Complexity: High
//  Created: 2026-05-31
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

// ═══ Hash / Noise Utilities ═══
fn hash21(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    let p3 = fract(vec3<f32>(p.x, p.y, p.x) * vec3<f32>(0.1031, 0.1030, 0.0973));
    let p4 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash21(i + vec2<f32>(0.0, 0.0)), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y
    );
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var pp = p;
    for (var i: i32 = 0; i < octaves; i++) {
        v += a * noise(pp);
        pp = pp * 2.0 + vec2<f32>(100.0);
        a *= 0.5;
    }
    return v;
}

// ═══ Mycelium Growth Function ═══
// Returns vec3: x=distance to nearest filament, y=generation/age, z=tip intensity
fn myceliumLayer(p: vec2<f32>, t: f32, timeScale: f32, seed: f32, growthParam: f32) -> vec3<f32> {
    var minDist = 100.0;
    var bestAge = 0.0;
    var bestTip = 0.0;

    let layerT = t * timeScale;
    let numRoots = 5;

    for (var r: i32 = 0; r < numRoots; r++) {
        let rootSeed = vec2<f32>(seed + f32(r) * 7.13, seed - f32(r) * 3.71);
        let rootAngle = hash21(rootSeed) * 6.2832;
        let rootRadius = 0.05 + hash21(rootSeed + 1.0) * 0.2;
        var pos = vec2<f32>(cos(rootAngle), sin(rootAngle)) * rootRadius;
        var dir = normalize(pos) * 0.5 + hash22(rootSeed) * 0.5;
        dir = normalize(dir);

        let segments = i32(15.0 + growthParam * 25.0);
        for (var i: i32 = 0; i < segments; i++) {
            let fi = f32(i);
            let segLen = 0.04 * (1.0 - fi / f32(segments)) * growthParam;

            // Organic wandering influenced by noise field
            let wander = noise(pos * 6.0 + layerT * 0.2 + fi * 0.3 + seed) * 2.0 - 1.0;
            let angle = atan2(dir.y, dir.x) + wander * 0.4;
            dir = vec2<f32>(cos(angle), sin(angle));

            let endPos = pos + dir * segLen;

            // Distance from p to line segment
            let pa = p - pos;
            let ba = endPos - pos;
            let h = clamp(dot(pa, ba) / (dot(ba, ba) + 0.0001), 0.0, 1.0);
            let dist = length(pa - ba * h);

            let age = fi / f32(segments);
            let tipness = 1.0 - age;

            if (dist < minDist) {
                minDist = dist;
                bestAge = age;
                bestTip = tipness;
            }

            // Branching
            if (hash21(pos * 100.0 + fi + seed) < growthParam * 0.25) {
                let branchAngle = angle + (hash21(pos + fi) - 0.5) * 1.6;
                let branchDir = vec2<f32>(cos(branchAngle), sin(branchAngle));
                let branchEnd = pos + branchDir * segLen * 0.6;
                let bpa = p - pos;
                let bba = branchEnd - pos;
                let bh = clamp(dot(bpa, bba) / (dot(bba, bba) + 0.0001), 0.0, 1.0);
                let bDist = length(bpa - bba * bh);
                if (bDist < minDist) {
                    minDist = bDist;
                    bestAge = age + 0.1;
                    bestTip = tipness * 0.7;
                }
            }

            pos = endPos;
        }
    }

    return vec3<f32>(minDist, bestAge, bestTip);
}

// ═══ Smooth bass envelope helper ═══
fn bassEnv(prev: f32, current: f32, attack: f32, release: f32) -> f32 {
    if (current > prev) {
        return mix(prev, current, attack);
    }
    return mix(prev, current, release);
}

// ═══ ACES Tone Mapping ═══
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = x * (x * 0.15 + 0.05) + 0.004;
  let b = x * (x * 0.15 + 0.50) + 0.06;
  return clamp(a / b - 0.0033, vec3<f32>(0.0), vec3<f32>(1.0));
}

// ═══ Fick's law nutrient diffusion ═══
// Fick's law: J = -D∇c, hyphal growth ~100-1000 μm/h
fn nutrientDiffusion(dist: f32, time: f32) -> f32 {
    let D = 0.5;
    return exp(-dist * dist / (4.0 * D * time));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));
    let uv = vec2<f32>(gid.xy) / res;
    let time = u.config.x;

    // Audio input
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Parameters
    let growthRate = mix(0.4, 1.5, u.zoom_params.x);
    let temporalDepth = mix(0.2, 1.0, u.zoom_params.y);
    let colorWarmth = u.zoom_params.z;
    let glowIntensity = mix(0.3, 2.0, u.zoom_params.w);

    // Mouse: spore burst position
    let mousePos = u.zoom_config.yz;

    // Smooth audio
    var prevBass = extraBuffer[0];
    let smoothBass = bassEnv(prevBass, bass, 0.15, 0.02);
    extraBuffer[0] = smoothBass;

    // Aspect ratio correction
    let aspect = res.x / res.y;
    let p = (uv - 0.5) * vec2<f32>(aspect, 1.0) * 2.0;

    // Mouse influence: spore burst - adds nutrient gradient near mouse
    let mp = (mousePos - 0.5) * vec2<f32>(aspect, 1.0) * 2.0;
    let mouseDist = length(p - mp);
    let mouseInfluence = exp(-mouseDist * 3.0) * 0.5;

    // ═══ MULTI-TEMPORAL LAYERS ═══
    // Layer 1: Ancient slow growth (bass-driven)
    let ancientTime = time * 0.02 * (1.0 + smoothBass * 0.5);
    let ancientSeed = floor(ancientTime * 0.5);
    let ancient = myceliumLayer(p, ancientTime, 0.3, ancientSeed, growthRate * 0.7 + mouseInfluence);

    // Layer 2: Middle generation (mids-driven)
    let midTime = time * 0.08 * (1.0 + mids * 0.4);
    let midSeed = floor(midTime * 0.8) + 100.0;
    let middle = myceliumLayer(p, midTime, 0.7, midSeed, growthRate * 0.9 + mouseInfluence * 0.7);

    // Layer 3: Rapid new tendrils (treble-driven)
    let newTime = time * 0.2 * (1.0 + treble * 0.8);
    let newSeed = floor(newTime * 1.2) + 200.0;
    let fresh = myceliumLayer(p, newTime, 1.5, newSeed, growthRate * 1.2 + mouseInfluence * 0.5);

    // ═══ COLOR AND COMPOSITING ═══
    // Ancient layer: faded gold/amber
    let ancientThick = 0.006;
    let ancientMask = smoothstep(ancientThick * 3.0, 0.0, ancient.x);
    let ancientAlpha = ancientMask * (0.2 + temporalDepth * 0.15);
    let ancientCol = mix(
        vec3<f32>(0.4, 0.3, 0.1),
        vec3<f32>(0.6, 0.5, 0.2),
        ancient.y
    ) * ancientAlpha;

    // Middle layer: warm white/cream
    let midThick = 0.004;
    let midMask = smoothstep(midThick * 2.5, 0.0, middle.x);
    let midAlpha = midMask * (0.4 + temporalDepth * 0.2);
    let midCol = mix(
        vec3<f32>(0.7, 0.6, 0.4),
        vec3<f32>(0.9, 0.85, 0.7),
        middle.z
    ) * midAlpha;

    // Fresh layer: bright white/gold with glowing tips
    let freshThick = 0.003;
    let freshMask = smoothstep(freshThick * 2.0, 0.0, fresh.x);
    let freshAlpha = freshMask * 0.9;
    let tipPulse = sin(time * 4.0 + fresh.y * 12.0) * 0.5 + 0.5;
    let tipGlow = fresh.z * exp(-fresh.x * 50.0) * glowIntensity * (0.6 + tipPulse * 0.4);
    let freshCol = mix(
        vec3<f32>(0.9, 0.85, 0.7),
        vec3<f32>(1.0, 0.95, 0.8),
        fresh.z
    ) * freshAlpha + vec3<f32>(1.0, 0.9, 0.5) * tipGlow;

    // Color warmth blend
    let coolTint = vec3<f32>(0.7, 0.8, 1.0);
    let warmTint = vec3<f32>(1.0, 0.9, 0.7);
    let tint = mix(coolTint, warmTint, colorWarmth);

    // Combine layers with depth
    var col = vec3<f32>(0.02, 0.015, 0.01); // Dark organic background
    col += ancientCol * tint;
    col += midCol * tint;
    col += freshCol * tint;

    // Audio pulse on overall brightness
    col *= 1.0 + smoothBass * 0.2 + mids * 0.1;

    // Spore burst glow near mouse
    let sporeBurst = mouseInfluence * (0.5 + treble * 0.5);
    col += vec3<f32>(0.8, 0.7, 0.3) * sporeBurst * 0.3;

    // Apply nutrient diffusion from mouse (Fick's law)
    let diffusion = nutrientDiffusion(mouseDist, time * 0.1 + 0.1);
    col += vec3<f32>(0.6, 0.5, 0.2) * diffusion * smoothBass * 0.2;

    // Temporal feedback: blend with previous frame for persistence
    let prev = textureLoad(dataTextureC, coord, 0).rgb;
    let decayRate = 0.92 + temporalDepth * 0.05;
    col = max(col, prev * decayRate);

    // Chromatic aberration
    let caStr = 0.003 * (1.0 + smoothBass) + ancient.x * 0.001;
    col = vec3<f32>(col.r + caStr, col.g, col.b - caStr * 0.5);

    // ACES tone mapping
    col = acesToneMap(col);

    // Vignette
    let vignette = 1.0 - length(uv - 0.5) * 0.6;
    col *= vignette;

    // Alpha: denser areas more opaque (for compositing)
    let alpha = clamp(ancientAlpha + midAlpha + freshAlpha + sporeBurst * 0.3, 0.0, 1.0);

    textureStore(dataTextureA, coord, vec4<f32>(col, alpha));
    textureStore(writeTexture, coord, vec4<f32>(col, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(ancient.y * 0.3 + middle.y * 0.3 + fresh.y * 0.4, 0.0, 0.0, 0.0));
}
