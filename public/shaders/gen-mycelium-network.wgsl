// ═══════════════════════════════════════════════════════════════════
//  Mycelium Network
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-14
//  Ideas: peripheral growth zone with interior autolysis (only the colony rim behind the growth front stays vital; older hyphae stale, fade and lose tip light); click-inoculated spore germination (germ tubes emerge from the clicked spore with linear apical extension and a Spitzenkörper glow)
//  A packing: ACES display RGBA in A (feedback history kept in display space; rgb = max-decayed network light, a = glow mass)
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
  zoom_params: vec4<f32>,  // .x = Growth Rate, .y = Branching Factor, .z = Nutrient Density, .w = Bioluminescence
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const HDR_CAP: f32 = 4.0;      // hard bound for feedback history energy
const GERM_LIFE: f32 = 4.5;    // seconds a clicked spore's germ tubes stay lit
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

// ── IDEA 2: click-inoculated spore germination ──
// A spore dropped at the click swells, then pushes out 2–4 germ tubes.
// Hyphae extend only at the apex, at a near-constant rate, so tube length is
// linear in age; each tube curves gently (bent at its midpoint) and carries a
// Spitzenkörper — the vesicle supply centre — as a bright point at its tip.
// Returns (tube mask, tip glow, spore body).
fn germinate(p: vec2<f32>, spore: vec2<f32>, age: f32, seed: f32, growthRate: f32, branching: f32) -> vec3<f32> {
    let extend = age * (0.10 + growthRate * 0.12);
    let reach = extend + 0.08;
    let rel = p - spore;
    if (dot(rel, rel) > reach * reach) { return vec3<f32>(0.0); }
    let life = 1.0 - smoothstep(GERM_LIFE * 0.6, GERM_LIFE, age);
    let swell = smoothstep(0.0, 0.35, age);
    let body = exp(-dot(rel, rel) / (0.00018 + swell * 0.00022)) * life;
    let lag = 0.35;  // germ tubes emerge after the spore has swollen
    let len = max(age - lag, 0.0) * (0.10 + growthRate * 0.12);
    var tube = 0.0;
    var tip = 0.0;
    let nTubes = 2 + i32(branching * 3.0);
    for (var k = 0; k < nTubes; k = k + 1) {
        let hk = hash21(vec2<f32>(seed, f32(k) * 7.13));
        let ang = seed * TAU + f32(k) * TAU / f32(nTubes) + (hk - 0.5) * 0.9;
        let dir = vec2<f32>(cos(ang), sin(ang));
        let perp = vec2<f32>(-dir.y, dir.x);
        let curl = (hk - 0.5) * 0.35 * len;
        let mid = spore + dir * len * 0.5 + perp * curl * 0.5;
        let apex = spore + dir * len + perp * curl;
        let d = min(distToSegment(p, spore, mid), distToSegment(p, mid, apex));
        tube = max(tube, smoothstep(0.006, 0.0, d));
        let ta = p - apex;
        tip = max(tip, exp(-dot(ta, ta) * 2600.0) * step(0.001, len));
    }
    return vec3<f32>(tube * life, tip * life, body);
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
fn generateMycelium(uv: vec2<f32>, t: f32, growthRate: f32, branching: f32, seed: vec2<f32>, mouseP: vec2<f32>, nutrientDensity: f32) -> MycelData {
    var minDist = 1000.0;
    var data = MycelData(1000.0, 0.0, 0.0, 0.0, 0.0);
    var prevTip = vec2<f32>(0.0);

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
            // Idea 1 — chemotaxis: Nutrient Density pulls wander toward the mouse well
            let toNut = mouseP - currentPos;
            let nutLen = max(length(toNut), 0.0001);
            currentDir = normalize(
                currentDir
                + vec2<f32>(cos(wanderAngle), sin(wanderAngle)) * 0.3
                + (toNut / nutLen) * nutrientDensity * 0.28
            );

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

                    // Idea 2 — anastomosis loop toward the sibling root when the tip is close
                    let otherAngle = rootAngle + 2.094;
                    let otherRoot = vec2<f32>(cos(otherAngle), sin(otherAngle)) * 0.1;
                    let fuseReach = 0.20 + nutrientDensity * 0.22;
                    if (length(branchEnd - otherRoot) < fuseReach) {
                        let fuseEnd = mix(branchEnd, otherRoot, 0.55);
                        let fuseDist = distToSegment(uv, branchEnd, fuseEnd);
                        if (fuseDist < minDist) {
                            minDist = fuseDist;
                            data = MycelData(fuseDist, age, 0.15, generation + 0.5, length(currentPos));
                        }
                    }
                }
            }

            currentPos = endPos;
            age = fi / f32(maxBranches);
            generation += 0.1;
        }

        // Tip-to-tip fusion with the previous root when they approach
        if (r > 0) {
            let tipReach = 0.16 + nutrientDensity * 0.20;
            if (length(currentPos - prevTip) < tipReach) {
                let tipFuse = distToSegment(uv, currentPos, prevTip);
                if (tipFuse < minDist) {
                    minDist = tipFuse;
                    data = MycelData(tipFuse, age, 0.2, generation, length(currentPos));
                }
            }
        }
        prevTip = currentPos;
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

    // Audio (canonical plasmaBuffer taps only)
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
    let held = clamp(u.zoom_config.w, 0.0, 1.0);

    // ── Bass transient (rising-edge) detector with frame-rate-independent
    //    decay — persistent state in the safe zone [133..135], single writer ──
    var kick = 0.0;
    if (arrayLength(&extraBuffer) > 138u) {
        if (global_id.x == 0u && global_id.y == 0u) {
            let prevBass = extraBuffer[133];
            let kickEnv = extraBuffer[134];
            let dt = clamp(t - extraBuffer[135], 0.0, 0.1);
            let rise = max(bass - prevBass, 0.0);
            extraBuffer[134] = max(kickEnv * exp(-dt * 5.0), min(rise * 6.0, 2.0));
            extraBuffer[133] = bass;
            extraBuffer[135] = t;
        }
        kick = clamp(extraBuffer[134], 0.0, 2.0);
    }

    // Parameters - safe randomization (all four sliders LIVE)
    let growthRate = mix(0.3, 2.0, u.zoom_params.x);       // Growth Rate → also SPEED
    let branching = mix(0.1, 0.8, u.zoom_params.y);        // Branching Factor
    let nutrientDensity = mix(0.3, 1.0, u.zoom_params.z);  // Nutrient Density
    let biolumIntensity = mix(0.5, 3.0, u.zoom_params.w);  // Bioluminescence

    // Aspect correction
    let aspect = resolution.x / resolution.y;
    let p = (uv - 0.5) * vec2<f32>(aspect, 1.0) * 2.0;
    let mouse = u.zoom_config.yz;
    let mouseP = (mouse - 0.5) * vec2<f32>(aspect, 1.0) * 2.0;

    // ── FAST MOTION: time-warped growth front (fast-in / smooth-out easing) ──
    let cycle = t * (0.05 + growthRate * 0.12) * (1.0 + bass * 0.3 + kick * 0.4);
    let growthPhase = fract(cycle);
    let seed = vec2<f32>(floor(cycle), 0.0);
    let frontEase = 1.0 - pow(1.0 - growthPhase, 3.0); // fast launch, soft landing
    let frontR = frontEase * 2.4;

    // Get mycelium data (coarse-culled traversal)
    let mycel = generateMycelium(p, t, growthRate, branching, seed, mouseP, nutrientDensity);
    let dist = mycel.dist;
    let age = mycel.age;
    let isTip = mycel.isTip;
    let generation = mycel.generation;

    // Growth-front visibility: branches ahead of the front are ghosted
    let grow = clamp((frontR - mycel.branchR) * 4.0 + 1.0, 0.15, 1.0);

    // ── IDEA 1: peripheral growth zone + interior autolysis ──
    // A fungal colony only extends in a band just behind its advancing margin;
    // the interior stales — vacuolated hyphae autolyse, go grey-translucent and
    // stop feeding their tips. Richer nutrients (and faster growth) widen the
    // vital zone. `behind` > 0 means the branch lies inside the front.
    let behind = frontR - mycel.branchR;
    let zoneWidth = 0.35 + growthRate * 0.2 + nutrientDensity * 0.35;
    let vitality = mix(0.22, 1.0, exp(-max(behind - zoneWidth, 0.0) * 2.4));

    // Earthy brown colors for hyphae (get darker with age; stale interior greys out)
    let youngCol = vec3<f32>(0.6, 0.45, 0.3);
    let oldCol = vec3<f32>(0.25, 0.15, 0.1);
    let staleCol = vec3<f32>(0.16, 0.15, 0.14);
    let hyphaeCol = mix(staleCol, mix(youngCol, oldCol, age), vitality);

    // Thickness varies with generation
    let thickness = 0.003 * (1.0 - generation * 0.1);

    // Hyphae visibility
    let hyphaeMask = smoothstep(thickness * 2.0, 0.0, dist) * grow;
    let hyphaeCore = smoothstep(thickness, 0.0, dist) * grow * mix(0.4, 1.0, vitality);

    // Bioluminescent tips
    let tipPulse = sin(t * 3.0 + age * 10.0) * 0.5 + 0.5;
    let tipGlow = isTip * exp(-dist * 30.0) * biolumIntensity * (0.5 + tipPulse * 0.5) * grow * vitality * vitality * (1.0 + treble * 0.3);
    let tipCol = vec3<f32>(0.2, 0.9, 0.4) * tipGlow;

    // ── FAST MOTION: traveling signal pulses racing along the hyphae ──
    // Closed-form in (age, t) — zero extra traversal cost; speed is driven by
    // the Growth Rate slider and surges with bass / kick transients.
    let pulseSpeed = 2.0 + growthRate * 4.0 + bass * 2.0 + kick * 3.0;
    let wave = fract(age * 1.5 - t * pulseSpeed * 0.12);
    let pulseBand = exp(-pow((wave - 0.5) * 5.0, 2.0));
    let pulseGlow = pulseBand * hyphaeMask * biolumIntensity * 0.55 * (0.6 + mids * 0.4) * mix(0.45, 1.0, vitality);
    let pulseCol = vec3<f32>(0.15, 0.8, 0.45) * pulseGlow;

    // Nutrient field (background glow, drifting faster, FFT-shimmered)
    let nutrient = fbm(p * 3.0 + vec2<f32>(t * 0.15, -t * 0.1), 4);
    let nutrientCol = vec3<f32>(0.1, 0.08, 0.05) * nutrient * nutrientDensity * (1.0 + mids * 0.4 + treble * 0.15);

    // Mouse = nutrient attractor (stays reactive at speed)
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
    let burstOrigin = select(vec2<f32>(0.0), mouseP, held > 0.5);
    let kickClamped = min(kick, 2.0);
    let burstR = (2.0 - kickClamped) * 1.1;
    let burstD = length(p - burstOrigin) - burstR;
    let burst = exp(-burstD * burstD * 49.0) * min(kick, 1.5);
    col += vec3<f32>(0.3, 0.9, 0.5) * burst * 0.5;

    // Click ripples → spore inoculation (IDEA 2)
    var germTube = 0.0;
    var germTip = 0.0;
    var germBody = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let rAge = t - rp.z;
        if (rAge >= 0.0 && rAge < GERM_LIFE) {
            let sporeP = (rp.xy - 0.5) * vec2<f32>(aspect, 1.0) * 2.0;
            let g = germinate(p, sporeP, rAge, hash21(rp.xy * 97.0 + rp.z), growthRate, branching);
            germTube = max(germTube, g.x);
            germTip = max(germTip, g.y);
            germBody = max(germBody, g.z);
        }
    }
    col = mix(col, youngCol * 1.25, germTube * 0.85);
    col += vec3<f32>(0.25, 1.0, 0.5) * germTip * biolumIntensity * (0.8 + bass * 0.4);
    col += vec3<f32>(0.75, 0.6, 0.35) * germBody * 0.9;

    // Vignette
    let vignette = 1.0 - length(uv - 0.5) * 0.5;
    col *= vignette;

    // ── Temporal feedback: persistent growth, but BOUNDED ──
    // History is hard-clamped ≤ HDR_CAP and fades quickly near cycle wrap so
    // the old colony clears for the next one (was unbounded max() saturation).
    // History now lives in ACES display space (A = display RGBA), exact load.
    let maxP = vec2<i32>(i32(resolution.x) - 1, i32(resolution.y) - 1);
    let prev = textureLoad(dataTextureC, clamp(pixel, vec2<i32>(0), maxP), 0);
    let hist = clamp(prev.rgb, vec3<f32>(0.0), vec3<f32>(1.0));
    let clearFade = smoothstep(1.0, 0.92, growthPhase);
    let decay = mix(0.90, 0.965, clearFade);
    let display = max(acesToneMap(min(col, vec3<f32>(HDR_CAP)) * (1.0 + bass * 0.1)), hist * decay);

    // Semantic alpha: bioluminescent mass of the network (never constant 1.0),
    // persisting with the same decay as the colour history.
    let glowNow = clamp(hyphaeMask * 0.7 + tipGlow * 0.3 + pulseGlow * 0.4 + burst * 0.3 + germTube * 0.6 + germTip * 0.4 + germBody * 0.3, 0.06, 1.0);
    let glowMass = clamp(max(glowNow, clamp(prev.a, 0.0, 1.0) * decay), 0.06, 1.0);
    let finalColor = vec4<f32>(display, glowMass);

    textureStore(writeTexture, pixel, finalColor);
    textureStore(dataTextureA, pixel, finalColor);
    // Real generated depth: hypha relief + age + pulse elevation + germ tubes
    let relief = clamp(hyphaeCore * 0.5 + age * 0.3 * vitality + pulseGlow * 0.2 + germTube * 0.35, 0.0, 1.0);
    textureStore(writeDepthTexture, pixel, vec4<f32>(relief, 0.0, 0.0, 0.0));
}
