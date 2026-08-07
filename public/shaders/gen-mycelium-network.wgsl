// ═══════════════════════════════════════════════════════════════════
//  Mycelium Network - Diffusion-limited aggregation like fungal mycelium
//  Category: generative
//  Features: procedural, branching, bioluminescent tips, audio-reactive,
//    mouse-interactive, fast-motion, traveling-pulses, burst-shockwave,
//    time-warp-growth, temporal-feedback, hdr-clamped, semantic-alpha
//  Created: 2026-03-22
//  Updated: 2026-08-06 (Batch 38 FAST MOTION — Optimizer pass)
//  By: Agent 4A
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
  config: vec4<f32>,       // .x = time (seconds), .y = rippleCount, .zw = resolution (width, height)
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (0–1 canvas: y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // .xyzw = user params p1…p4 (mapped from UI sliders)
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const HDR_CAP: f32 = 4.0;      // hard bound for feedback history energy
const CULL_MARGIN: f32 = 0.12; // coarse-cull box margin (covers thickness + glow reach)

// Hash and noise functions
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

// FBM
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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Distance to line segment
fn distToSegment(uv: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
    let pa = uv - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / (dot(ba, ba) + 0.0001), 0.0, 1.0);
    return length(pa - ba * h);
}

// Mycelium sample result
struct MycelData {
    dist: f32,       // distance to nearest hypha segment
    age: f32,        // normalized age along branch (0 root → 1 tip)
    isTip: f32,      // tip weight
    generation: f32, // branching generation
    branchR: f32,    // radial distance of nearest branch from colony center
};

// Generate mycelium branches.
// OPTIMIZER: every distance evaluation is gated behind a cheap axis-aligned
// bounding-box test (CULL_MARGIN). The walk (noise + direction) must always run
// — the branch path is sequential — but ~80–95% of segment SDF evaluations are
// pruned for pixels far from the colony.
fn generateMycelium(uv: vec2<f32>, t: f32, growthRate: f32, branching: f32, seed: vec2<f32>) -> MycelData {
    var minDist = 1000.0;
    var data = MycelData(1000.0, 0.0, 0.0, 0.0, 0.0);

    // Generate branching structure
    let numRoots = 3;
    for (var r: i32 = 0; r < numRoots; r++) {
        let rootAngle = f32(r) * 2.094 + hash21(seed + f32(r)) * 0.5;
        let rootPos = vec2<f32>(cos(rootAngle), sin(rootAngle)) * 0.1;

        var currentPos = rootPos;
        var currentDir = vec2<f32>(cos(rootAngle), sin(rootAngle));
        var age = 0.0;
        var generation = 0.0;

        // Grow branches (bounded iteration count)
        let maxBranches = min(i32(20.0 + branching * 50.0), 70);
        for (var i: i32 = 0; i < maxBranches; i++) {
            let fi = f32(i);

            // Branch segment length shrinks with age
            let segLen = 0.05 * (1.0 - fi / f32(maxBranches)) * growthRate;

            // Wandering direction (smooth noise — temporally coherent)
            let wanderAngle = noise(currentPos * 5.0 + t * 0.1 + fi) * 1.5;
            currentDir = normalize(currentDir + vec2<f32>(cos(wanderAngle), sin(wanderAngle)) * 0.3);

            let endPos = currentPos + currentDir * segLen;

            // ── Coarse cull: skip SDF + side-branch work unless the pixel is
            //    near this segment's bounding box ──
            let lo = min(currentPos, endPos) - vec2<f32>(CULL_MARGIN);
            let hi = max(currentPos, endPos) + vec2<f32>(CULL_MARGIN);
            if (all(uv >= lo) && all(uv <= hi)) {
                let dist = distToSegment(uv, currentPos, endPos);

                // Is this a tip?
                let isTip = 1.0 - fi / f32(maxBranches);

                if (dist < minDist) {
                    minDist = dist;
                    data = MycelData(dist, age, isTip, generation, length(currentPos));
                }

                // Branch probabilistically
                let branchProb = branching * 0.3 * (1.0 - fi / f32(maxBranches));
                if (hash21(currentPos + fi) < branchProb) {
                    // Create side branch
                    let branchAngle = wanderAngle + 0.8;
                    let branchDir = normalize(currentDir + vec2<f32>(cos(branchAngle), sin(branchAngle)));
                    let branchEnd = currentPos + branchDir * segLen * 0.7;

                    let branchDist = distToSegment(uv, currentPos, branchEnd);
                    if (branchDist < minDist) {
                        minDist = branchDist;
                        data = MycelData(branchDist, age, isTip * 0.8, generation + 1.0, length(currentPos));
                    }
                }
            }

            currentPos = endPos;
            age = fi / f32(maxBranches);
            generation += 0.1;
        }
    }

    return data;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let resolution = u.config.zw;
    // Bounds guard — mandatory
    if (pixel.x >= i32(resolution.x) || pixel.y >= i32(resolution.y)) { return; }

    let uv = vec2<f32>(pixel) / resolution;
    let t = u.config.x;

    // Audio (canonical taps) + guarded engine FFT bins 1–8
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    var fftLo = 0.0;
    var fftMid = 0.0;
    let bufLen = arrayLength(&extraBuffer);
    if (bufLen > 13u) {
        fftLo = (extraBuffer[6] + extraBuffer[7] + extraBuffer[8]) * 0.3333;
        fftMid = (extraBuffer[9] + extraBuffer[10] + extraBuffer[11]) * 0.3333;
    }

    // ── Bass transient (rising-edge) detector with frame-rate-independent
    //    decay — persistent state in the safe zone [133..135], single writer ──
    if (global_id.x == 0u && global_id.y == 0u && bufLen > 135u) {
        let prevBass = extraBuffer[133];
        let kickEnv = extraBuffer[134];
        let dt = clamp(t - extraBuffer[135], 0.0, 0.1);
        let rise = max(bass - prevBass, 0.0);
        extraBuffer[134] = max(kickEnv * exp(-dt * 5.0), min(rise * 6.0, 2.0));
        extraBuffer[133] = bass;
        extraBuffer[135] = t;
    }
    let kick = select(0.0, extraBuffer[134], bufLen > 134u);

    // Parameters - safe randomization (all four sliders LIVE)
    let growthRate = mix(0.3, 2.0, u.zoom_params.x);       // Growth Rate → also SPEED
    let branching = mix(0.1, 0.8, u.zoom_params.y);        // Branching Factor
    let nutrientDensity = mix(0.3, 1.0, u.zoom_params.z);  // Nutrient Density
    let biolumIntensity = mix(0.5, 3.0, u.zoom_params.w);  // Bioluminescence

    // Aspect correction
    let aspect = resolution.x / resolution.y;
    let p = (uv - 0.5) * vec2<f32>(aspect, 1.0) * 2.0;

    // ── FAST MOTION: time-warped growth front (fast-in / smooth-out easing) ──
    let cycle = t * (0.05 + growthRate * 0.12) * (1.0 + bass * 0.3 + kick * 0.4);
    let growthPhase = fract(cycle);
    let seed = vec2<f32>(floor(cycle), 0.0);
    let frontEase = 1.0 - pow(1.0 - growthPhase, 3.0); // fast launch, soft landing
    let frontR = frontEase * 2.4;

    // Get mycelium data (coarse-culled traversal)
    let mycel = generateMycelium(p, t, growthRate, branching, seed);
    let dist = mycel.dist;
    let age = mycel.age;
    let isTip = mycel.isTip;
    let generation = mycel.generation;

    // Growth-front visibility: branches ahead of the front are ghosted
    let grow = clamp((frontR - mycel.branchR) * 4.0 + 1.0, 0.15, 1.0);

    // Earthy brown colors for hyphae (get darker with age)
    let youngCol = vec3<f32>(0.6, 0.45, 0.3);
    let oldCol = vec3<f32>(0.25, 0.15, 0.1);
    let hyphaeCol = mix(youngCol, oldCol, age);

    // Thickness varies with generation
    let thickness = 0.003 * (1.0 - generation * 0.1);

    // Hyphae visibility
    let hyphaeMask = smoothstep(thickness * 2.0, 0.0, dist) * grow;
    let hyphaeCore = smoothstep(thickness, 0.0, dist) * grow;

    // Bioluminescent tips
    let tipPulse = sin(t * 3.0 + age * 10.0) * 0.5 + 0.5;
    let tipGlow = isTip * exp(-dist * 30.0) * biolumIntensity * (0.5 + tipPulse * 0.5) * grow;
    let tipCol = vec3<f32>(0.2, 0.9, 0.4) * tipGlow;

    // ── FAST MOTION: traveling signal pulses racing along the hyphae ──
    // Closed-form in (age, t) — zero extra traversal cost; speed is driven by
    // the Growth Rate slider and surges with bass / kick transients.
    let pulseSpeed = 2.0 + growthRate * 4.0 + bass * 2.0 + kick * 3.0;
    let wave = fract(age * 1.5 - t * pulseSpeed * 0.12);
    let pulseBand = exp(-pow((wave - 0.5) * 5.0, 2.0));
    let pulseGlow = pulseBand * hyphaeMask * biolumIntensity * 0.55 * (0.6 + mids * 0.4);
    let pulseCol = vec3<f32>(0.15, 0.8, 0.45) * pulseGlow;

    // Nutrient field (background glow, drifting faster, FFT-shimmered)
    let nutrient = fbm(p * 3.0 + vec2<f32>(t * 0.15, -t * 0.1), 4);
    let nutrientCol = vec3<f32>(0.1, 0.08, 0.05) * nutrient * nutrientDensity * (1.0 + fftMid * 0.6 + treble * 0.15);

    // Mouse = nutrient attractor (stays reactive at speed)
    let mouse = u.zoom_config.yz;
    let mouseP = (mouse - 0.5) * vec2<f32>(aspect, 1.0) * 2.0;
    let mouseD2 = dot(p - mouseP, p - mouseP);
    let mouseNut = exp(-mouseD2 * 3.0);
    let mouseCol = vec3<f32>(0.1, 0.25, 0.12) * mouseNut * nutrientDensity * (0.4 + mids * 0.5);

    // Combine
    var col = nutrientCol + mouseCol;
    col = mix(col, hyphaeCol, hyphaeMask);
    col = col + vec3<f32>(0.3, 0.2, 0.15) * hyphaeCore * 0.5;
    col = col + tipCol + pulseCol;

    // Age rings chasing the growth front
    let ringDist = length(p) - frontR;
    let rings = sin(ringDist * 20.0) * 0.5 + 0.5;
    col = col + hyphaeCol * rings * 0.1 * (1.0 - age) * exp(-ringDist * ringDist * 2.0);

    // ── FAST MOTION: bass-kick spore-burst shockwave ──
    // Ring expands as the kick envelope decays (frame-rate independent);
    // origin follows the mouse while pressed, colony center otherwise.
    let burstOrigin = select(vec2<f32>(0.0), mouseP, u.zoom_config.w > 0.5);
    let kickClamped = min(kick, 2.0);
    let burstR = (2.0 - kickClamped) * 1.1;
    let burstD = length(p - burstOrigin) - burstR;
    let burst = exp(-burstD * burstD * 49.0) * min(kick, 1.5);
    col += vec3<f32>(0.3, 0.9, 0.5) * burst * 0.5;

    // Vignette
    let vignette = 1.0 - length(uv - 0.5) * 0.5;
    col *= vignette;

    // ── Temporal feedback: persistent growth, but BOUNDED ──
    // History is hard-clamped ≤ HDR_CAP and fades quickly near cycle wrap so
    // the old colony clears for the next one (was unbounded max() saturation).
    let prev = textureLoad(dataTextureC, pixel, 0);
    let hist = min(prev.rgb, vec3<f32>(HDR_CAP));
    let clearFade = smoothstep(1.0, 0.92, growthPhase);
    col = max(col, hist * mix(0.90, 0.965, clearFade));

    // Semantic alpha: bioluminescent mass of the network (never constant 1.0)
    let glowMass = clamp(hyphaeMask * 0.7 + tipGlow * 0.3 + pulseGlow * 0.4 + burst * 0.3, 0.06, 1.0);

    // Feedback state written EVERY frame (HDR, clamped)
    textureStore(dataTextureA, pixel, vec4<f32>(min(col, vec3<f32>(HDR_CAP)), glowMass));
    textureStore(writeTexture, pixel, vec4<f32>(acesToneMap(col), glowMass));
    // Real generated depth: hypha relief + age + pulse elevation
    let relief = clamp(hyphaeCore * 0.5 + age * 0.3 + pulseGlow * 0.2, 0.0, 1.0);
    textureStore(writeDepthTexture, pixel, vec4<f32>(relief, 0.0, 0.0, 0.0));
}
