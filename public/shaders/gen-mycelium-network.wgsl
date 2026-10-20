// ═══════════════════════════════════════════════════════════════════
//  Mycelium Network — DLA-style wandering-branch fungus that feeds on music
//  Category: generative
//  Features: audio-reactive, bass_env growth pulse, mids hue-shift,
//            treble tip-sparkle, semantic-alpha, temporal-feedback,
//            aces-tone-map, ign-dither, bioluminescent-tips
//  Complexity: Medium
//  Chunks From: generateMycelium (DLA branch walker), bass_env,
//               hue_preserve_clamp, aces, ign
//  Repaired: 2026-07-18
//  By: Kimi Swarm — Algorithmist + Visualist (soul: Agent 4A, 2026-03-22)
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
  config: vec4<f32>,       // x=Time, y=delta_time, zw=resolution
  zoom_config: vec4<f32>,  // x=zoom, yz=mouse_uv, w=mouse_down
  zoom_params: vec4<f32>,  // xyzw = user params p1…p4
  ripples: array<vec4<f32>, 50>,
};

// ── Kimi Graphical Tactics ────────────────────────────────────────
fn hue_preserve_clamp(c: vec3<f32>, max_lum: f32) -> vec3<f32> {
    let l = dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
    let s = min(1.0, max_lum / max(l, 1e-4));
    return c * s;
}
fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x*(a*x+b))/(x*(c*x+d)+e), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn ign(p: vec2<f32>) -> f32 {
    return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}
fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
    let k = select(release, attack, bass > prev);
    return mix(prev, bass, k);
}

// ── Hash & noise stack (original character preserved) ─────────────
fn hash21(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
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

// ── Segment-distance SDF ──────────────────────────────────────────
fn distToSegment(uv: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
    let pa = uv - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / (dot(ba, ba) + 0.0001), 0.0, 1.0);
    return length(pa - ba * h);
}

// ── DLA-style wandering-branch generator (the soul — preserved) ───
fn generateMycelium(uv: vec2<f32>, t: f32, growthRate: f32, branching: f32, seed: vec2<f32>) -> vec4<f32> {
    var minDist = 1000.0;
    var branchData = vec4<f32>(0.0); // x=dist, y=age, z=isTip, w=generation

    let numRoots = 3;
    for (var r: i32 = 0; r < numRoots; r++) {
        let rootAngle = f32(r) * 2.094 + hash21(seed + f32(r)) * 0.5;
        let rootPos = vec2<f32>(cos(rootAngle), sin(rootAngle)) * 0.1;

        var currentPos = rootPos;
        var currentDir = vec2<f32>(cos(rootAngle), sin(rootAngle));
        var age = 0.0;
        var generation = 0.0;

        let maxBranches = i32(20.0 + branching * 50.0);
        for (var i: i32 = 0; i < maxBranches; i++) {
            let fi = f32(i);

            // Branch length shrinks as the hypha matures
            let length = 0.05 * (1.0 - fi / f32(maxBranches)) * growthRate;

            // Noise-steered wandering direction
            let wanderAngle = noise(currentPos * 5.0 + t * 0.1 + fi) * 1.5;
            currentDir = normalize(currentDir + vec2<f32>(cos(wanderAngle), sin(wanderAngle)) * 0.3);

            let endPos = currentPos + currentDir * length;
            let dist = distToSegment(uv, currentPos, endPos);
            let isTip = 1.0 - fi / f32(maxBranches);

            if (dist < minDist) {
                minDist = dist;
                branchData = vec4<f32>(dist, age, isTip, generation);
            }

            // Probabilistic side branches
            let branchProb = branching * 0.3 * (1.0 - fi / f32(maxBranches));
            if (hash21(currentPos + fi) < branchProb) {
                let branchAngle = wanderAngle + 0.8;
                let branchDir = normalize(currentDir + vec2<f32>(cos(branchAngle), sin(branchAngle)));
                let branchEnd = currentPos + branchDir * length * 0.7;
                let branchDist = distToSegment(uv, currentPos, branchEnd);
                if (branchDist < minDist) {
                    minDist = branchDist;
                    branchData = vec4<f32>(branchDist, age, isTip * 0.8, generation + 1.0);
                }
            }

            currentPos = endPos;
            age = fi / f32(maxBranches);
            generation += 0.1;
        }
    }

    return vec4<f32>(minDist, branchData.y, branchData.z, branchData.w);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv = vec2<f32>(pixel) / res;
    let t = u.config.x;

    // Audio: the fungus feeds on music
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Bass envelope — fast attack, slow release (persisted in extraBuffer[0])
    let bassEnv = bass_env(extraBuffer[0], bass, 0.5, 0.06);
    extraBuffer[0] = bassEnv;

    // Parameters — bass pulses growth rate and tip bioluminescence
    let growthRate = mix(0.3, 2.0, u.zoom_params.x) * (0.55 + bassEnv * 0.9);
    let branching = mix(0.1, 0.8, u.zoom_params.y);
    let nutrientDensity = mix(0.3, 1.0, u.zoom_params.z);
    let biolumIntensity = mix(0.5, 3.0, u.zoom_params.w) * (0.7 + bassEnv * 0.8);

    let aspect = res.x / res.y;
    let p = (uv - 0.5) * vec2<f32>(aspect, 1.0) * 2.0;

    // Animated seed for continuous growth cycles
    let growthPhase = fract(t * 0.05 * growthRate);
    let seed = vec2<f32>(floor(t * 0.05 * growthRate), 0.0);

    let mycel = generateMycelium(p, t, growthRate, branching, seed);
    let dist = mycel.x;
    let age = mycel.y;
    let isTip = mycel.z;
    let generation = mycel.w;

    // Earthy brown hyphae, darkening with age
    let hyphaeCol = mix(vec3<f32>(0.6, 0.45, 0.3), vec3<f32>(0.25, 0.15, 0.1), age);

    let thickness = 0.003 * (1.0 - generation * 0.1);
    let hyphaeMask = smoothstep(thickness * 2.0, 0.0, dist);
    let hyphaeCore = smoothstep(thickness, 0.0, dist);

    // Bioluminescent tips: bass pulse + sharp treble sparkle bursts
    let tipPulse = sin(t * 3.0 + age * 10.0) * 0.5 + 0.5;
    var tipGlow = isTip * exp(-dist * 30.0) * biolumIntensity * (0.5 + tipPulse * 0.5);
    tipGlow *= 1.0 + treble * 2.0 * step(0.7, isTip);
    let tipCol = vec3<f32>(0.2, 0.9, 0.4) * tipGlow;

    // Nutrient field: mids shift the hue from umber toward teal
    let nutrient = fbm(p * 3.0 + t * 0.1, 4);
    let nutrientHue = mix(vec3<f32>(0.1, 0.08, 0.05), vec3<f32>(0.05, 0.10, 0.09), clamp(mids * 0.6, 0.0, 1.0));
    let nutrientCol = nutrientHue * nutrient * nutrientDensity;

    var col = nutrientCol;
    col = mix(col, hyphaeCol, hyphaeMask);
    col += vec3<f32>(0.3, 0.2, 0.15) * hyphaeCore * 0.5;
    col += tipCol;

    // Age rings around growth centers
    let ringDist = length(p) - growthPhase * 2.0;
    let rings = sin(ringDist * 20.0) * 0.5 + 0.5;
    col += hyphaeCol * rings * 0.1 * (1.0 - age);

    // Vignette
    let vignette = 1.0 - length(uv - 0.5) * 0.5;
    col *= vignette;

    // Tone-map chain BEFORE feedback so trails never blow out
    col = hue_preserve_clamp(col, 1.4);
    col = aces(col * (0.9 + bassEnv * 0.25));
    col += vec3<f32>((ign(vec2<f32>(pixel)) - 0.5) / 255.0);

    // Persistent growth feedback
    let prev = textureLoad(dataTextureC, pixel, 0).rgb;
    col = max(col, prev * 0.98);
    textureStore(dataTextureA, pixel, vec4<f32>(col, 1.0));

    // Semantic alpha: hyphae presence + tip glow, nutrient stays translucent
    let alpha = clamp(hyphaeMask * 0.85 + tipGlow * 0.6 + nutrient * 0.15, 0.0, 1.0);
    textureStore(writeTexture, pixel, vec4<f32>(col * alpha, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(age * 0.5, 0.0, 0.0, 0.0));
}
