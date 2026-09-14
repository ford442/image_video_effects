// ═══════════════════════════════════════════════════════════════════
//  Physarum (Slime Mold) Sacred Geometry
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-14
//  Ideas: Flower-of-Life compass construction (agents orbit lattice circles, chemotactically bent onto shared strands); Tero flux-adaptive tube reinforcement and pruning
//  A packing: ACES display RGBA in A (alpha = pheromone trail density, fed back from C.a as the Physarum trail field)
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
    config: vec4<f32>,       // x=Time, y=rippleCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
    zoom_params: vec4<f32>,  // x=Intensity, y=Speed, z=Scale, w=Mouse Influence
    ripples: array<vec4<f32>, 50>,
};

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn applyGenerativePrimaryControls(color: vec4<f32>) -> vec4<f32> {
  let primaryIntensity = mix(0.55, 1.45, clamp(u.zoom_params.x, 0.0, 1.0));
  let speedPulse = 0.92 + 0.16 * (0.5 + 0.5 * sin(u.config.x * mix(0.25, 5.0, clamp(u.zoom_params.y, 0.0, 1.0))));
  let detailContrast = mix(0.75, 1.6, clamp(u.zoom_params.z, 0.0, 1.0));
  let mouseDistance = length(u.zoom_config.yz - vec2<f32>(0.5));
  let mouseInfluence = mix(0.95, 1.15, clamp(u.zoom_params.w * mouseDistance * 2.0, 0.0, 1.0));
  let controlled = pow(max(color.rgb * primaryIntensity * speedPulse * mouseInfluence, vec3<f32>(0.0)), vec3<f32>(1.0 / detailContrast));
  return vec4<f32>(controlled, color.a);
}

// Hashing primitives
fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}
fn fbm(p: vec2<f32>, oct: i32) -> f32 {
    var s = 0.0;
    var a = 0.5;
    var f = 1.0;
    for (var i = 0; i < oct; i = i + 1) {
        s += a * valueNoise(p * f);
        f *= 2.0;
        a *= 0.5;
    }
    return s;
}
fn domainWarp(p: vec2<f32>, t: f32) -> vec2<f32> {
    let q = vec2<f32>(fbm(p + vec2<f32>(0.0, t), 3), fbm(p + vec2<f32>(5.2, 1.3), 3));
    return p + 0.25 * q;
}

// Curl noise steers agents along the FBM gradient
fn curlNoise(p: vec2<f32>, t: f32) -> vec2<f32> {
    let e = 0.5;
    let n0 = fbm(p + vec2<f32>(e, 0.0) + t, 4);
    let n1 = fbm(p - vec2<f32>(e, 0.0) + t, 4);
    let n2 = fbm(p + vec2<f32>(0.0, e) + t, 4);
    let n3 = fbm(p - vec2<f32>(0.0, e) + t, 4);
    return vec2<f32>(n3 - n2, n0 - n1) / (2.0 * e);
}

// Hexagonal SDF sacred-geometry mask
fn hexDist(p: vec2<f32>) -> f32 {
    let s = vec2<f32>(1.0, 1.7320508);
    let h = s * 0.5;
    let a = abs(p - s * floor((p + h) / s)) - h;
    return max(a.x, a.y);
}
fn sacredMask(uv: vec2<f32>, t: f32) -> f32 {
    let h1 = smoothstep(0.06, 0.0, hexDist(uv * 12.0));
    let h2 = smoothstep(0.04, 0.0, hexDist(uv * 24.0 + vec2<f32>(t * 0.1)));
    return clamp(h1 + h2 * 0.5, 0.0, 1.0);
}

// Mandelbrot orbit trap for fractal color accents
fn mandelbrotTrap(c: vec2<f32>) -> f32 {
    var z = vec2<f32>(0.0);
    var trap = 100.0;
    for (var i = 0; i < 16; i = i + 1) {
        z = vec2<f32>(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y) + c;
        trap = min(trap, length(z - vec2<f32>(0.3, 0.0)));
        if (dot(z, z) > 4.0) { break; }
    }
    return trap;
}

// Sense trail (C.a) + domain-warped food + geometry aura (branchless bounds)
fn sense(pos: vec2<f32>, angleOffset: f32, sensorDist: f32) -> f32 {
    let angle = angleOffset;
    let dir = vec2<f32>(cos(angle), sin(angle));
    let sensorPos = pos + dir * sensorDist;
    let res = vec2<f32>(u.config.z, u.config.w);
    let inBounds = step(0.0, sensorPos.x) * step(sensorPos.x, res.x - 1.0) *
                   step(0.0, sensorPos.y) * step(sensorPos.y, res.y - 1.0);
    let clampedPos = clamp(sensorPos, vec2<f32>(0.0), res - 1.0);
    let trail = textureLoad(dataTextureC, vec2<i32>(clampedPos), 0).a;
    let uv = sensorPos / res;
    let warp = domainWarp(uv * 4.0, u.config.x * 0.1);
    let foodColor = textureSampleLevel(readTexture, u_sampler, clamp(warp, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    let food = dot(foodColor, vec3<f32>(0.333));
    let geo = sacredMask(uv, u.config.x);
    return inBounds * (trail * (1.0 + geo * 0.5) + food * 2.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let coords = vec2<i32>(global_id.xy);
    let res = vec2<i32>(i32(u.config.z), i32(u.config.w));
    if (coords.x >= res.x || coords.y >= res.y) { return; }

    let fres = vec2<f32>(res);
    let time = u.config.x;
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

    let intensity = clamp(u.zoom_params.x, 0.0, 1.0);
    let speed = clamp(u.zoom_params.y, 0.0, 1.0);
    let scale = clamp(u.zoom_params.z, 0.0, 1.0);
    let mouseInf = clamp(u.zoom_params.w, 0.0, 1.0);

    // Former per-agent constants, kept at their old defaults via the sliders.
    let sensorAngle = intensity;                          // 0.5 rad at default (was zoom_params.x)
    let turnSpeed = 0.5 + bass * 2.0;
    let pxScale = fres.y / 720.0;
    let moveSpeed = 1.5 * (speed / 0.5) * pxScale;        // px/frame, 1.5 at default (old moveSpeed)
    let S = fres.y * mix(0.04, 0.12, scale);              // Flower-of-Life lattice spacing = circle radius
    let sensorDist = S * 0.18 * (0.5 + speed);
    let sigma = max(1.1, 1.1 * pxScale);
    let maxOff = S * 0.07;
    let p = vec2<f32>(coords) + 0.5;

    // Mouse: hover repels agents (old 120px -> 80px band, scaled by Mouse Influence);
    // held mouse becomes an oat-flake food source that draws orbits in.
    let mousePos = u.zoom_config.yz * fres;
    let repR = 240.0 * mouseInf * pxScale;
    let held = u.zoom_config.w > 0.5;
    let mousePush = S * 0.3;

    // ── Native idea 1: Flower-of-Life compass construction ──────────────
    // Stateless hashed agents ride circles of radius S centred on a triangular
    // lattice. Each frame an agent senses the previous trail (C.a) with the
    // classic three sensors and is bent sideways onto the stronger strand.
    let rowH = S * 0.8660254;
    let reach = S * 0.08 + maxOff + mousePush + 4.0 * sigma;
    let j0 = i32(floor(p.y / rowH + 0.5));
    var deposit = 0.0;
    for (var dj = -2; dj <= 2; dj = dj + 1) {
        let j = j0 + dj;
        let xOff = select(0.0, S * 0.5, (abs(j) % 2) == 1);
        let i0 = i32(floor((p.x - xOff) / S + 0.5));
        for (var di = -2; di <= 2; di = di + 1) {
            let i = i0 + di;
            let center = vec2<f32>(f32(i) * S + xOff, f32(j) * rowH);
            let cellId = vec2<f32>(f32(i), f32(j));
            if (abs(length(p - center) - S) > reach) { continue; }
            let orbitDir = select(-1.0, 1.0, hash21(cellId + vec2<f32>(7.1, 3.3)) > 0.5);
            let phase0 = hash21(cellId) * 6.28318;
            let omega = moveSpeed * 60.0 / S;
            for (var k = 0; k < 3; k = k + 1) {
                let phi = phase0 + f32(k) * 2.0943951 + orbitDir * omega * time;
                let radial = vec2<f32>(cos(phi), sin(phi));
                var q = center + radial * S;
                if (length(q - p) > reach) { continue; }

                // Curl-noise steering bias: orbit radius wobble
                let curl = curlNoise(center * 0.02, time * 0.2);
                q += radial * S * clamp(curl.x * 0.3 * (1.0 + mids), -0.08, 0.08);

                // Mouse repulsion / attraction
                let toMouse = q - mousePos;
                let dm = max(length(toMouse), 1e-3);
                let push = smoothstep(repR, repR * 0.667, dm);
                q += (toMouse / dm) * push * mousePush * select(1.0, -1.0, held);

                // Three-sensor chemotaxis (old decision logic, branchless)
                let heading = phi + orbitDir * 1.5707963;
                let wF = sense(q, heading, sensorDist);
                let wL = sense(q, heading + sensorAngle, sensorDist);
                let wR = sense(q, heading - sensorAngle, sensorDist);
                let agentSeed = cellId * 1.618 + vec2<f32>(f32(k) * 11.3, floor(time * 1.5));
                let randomDir = select(-1.0, 1.0, hash21(agentSeed) > 0.5);
                let forwardWins = select(0.0, 1.0, wF >= wL && wF >= wR);
                let pinWheel = select(0.0, 1.0, wF < wL && wF < wR);
                let leftWins = select(0.0, 1.0, wL > wR);
                let rightWins = select(0.0, 1.0, wR > wL);
                let turn = (1.0 - forwardWins) * (
                    pinWheel * randomDir * turnSpeed * sensorAngle +
                    (1.0 - pinWheel) * (leftWins - rightWins) * turnSpeed * sensorAngle
                );
                let leftNormal = vec2<f32>(cos(heading + 1.5707963), sin(heading + 1.5707963));
                q += leftNormal * clamp(turn * 2.0, -1.0, 1.0) * maxOff;

                let dq = p - q;
                deposit += exp(-dot(dq, dq) / (2.0 * sigma * sigma));
            }
        }
    }

    // Click ripples: a compass circle of radius S is drawn out from each click
    // (the next seed circle of the construction), laid straight into the trail.
    let rippleCount = min(u32(u.config.y), 50u);
    for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
        let rp = u.ripples[ri];
        let age = time - rp.z;
        if (age >= 0.0 && age < 2.5) {
            let rr = S * min(age / 0.8, 1.0);
            let dr = length(p - rp.xy * fres) - rr;
            let fade = select(1.0, exp(-(age - 0.8) * 3.0), age > 0.8);
            deposit += exp(-dr * dr / (4.5 * sigma * sigma)) * fade * 0.6;
        }
    }

    // Blur & decay with branchless border weighting (trail lives in C.a)
    var sum = 0.0;
    var count = 0.0;
    for (var i = -1; i <= 1; i = i + 1) {
        for (var j = -1; j <= 1; j = j + 1) {
            let nCoord = coords + vec2<i32>(i, j);
            let inBounds = select(0.0, 1.0, nCoord.x >= 0 && nCoord.y >= 0 && nCoord.x < res.x && nCoord.y < res.y);
            let samplePos = clamp(nCoord, vec2<i32>(0), res - vec2<i32>(1));
            sum += inBounds * textureLoad(dataTextureC, samplePos, 0).a;
            count += inBounds;
        }
    }
    let blurResult = sum / max(count, 1.0);
    let prevTrail = textureLoad(dataTextureC, coords, 0).a;

    // ── Native idea 2: Tero flux-adaptive tubes ─────────────────────────
    // dD/dt = f(|Q|) - D: strands carrying flux gain conductance (slower decay,
    // stronger deposition); idle strands thin out and are pruned.
    let conductance = smoothstep(0.06, 0.6, blurResult);
    let decayRate = mix(0.94, 0.985, conductance);
    let diffused = mix(prevTrail, blurResult, 0.4) * decayRate;
    let teroGain = 0.6 + 0.9 * conductance;

    // Pheromone deposition by agents passing this pixel
    let uv = vec2<f32>(coords) / fres;
    let geo = sacredMask(uv, time);
    let depositGain = 0.5 * (1.0 + geo) * teroGain * mix(0.55, 1.45, intensity) * (1.0 + bass * 0.4);
    let trailDensity = clamp(diffused + deposit * depositGain, 0.0, 1.0);

    // Procedural color mapping with geometry + orbit trap accents
    let trap = mandelbrotTrap((uv - 0.5) * 2.5);
    let accent = exp(-trap * 5.0) * (0.5 + treble * 0.5);
    let t = trailDensity * 2.0 + geo * 0.6 + accent * 0.4;
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.263, 0.416, 0.557);
    var colorVec = a + b * cos(6.28318 * (c * t + d));
    // Thick, high-conductance tubes glow (protoplasmic streaming)
    colorVec += colorVec * smoothstep(0.45, 1.0, trailDensity) * conductance * (0.35 + mids * 0.3);

    // Composite with original video
    let vidColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let coverage = clamp(trailDensity + geo * 0.4 + accent * 0.3, 0.0, 1.0);
    let mixed = mix(vidColor.rgb, colorVec, clamp(trailDensity + geo * 0.25, 0.0, 1.0));

    // Held mouse: warm oat-flake glow at the food source
    var food = vec3<f32>(0.0);
    if (held) {
        let dmp = length(p - mousePos) / max(S * 0.35, 1.0);
        food = vec3<f32>(1.0, 0.85, 0.45) * exp(-dmp * dmp) * 0.4;
    }

    let controlled = applyGenerativePrimaryControls(vec4<f32>(mixed + food, 1.0));
    let display = acesToneMap(controlled.rgb * (1.0 + bass * 0.1));
    let finalColor = vec4<f32>(display, trailDensity);

    // Depth-aware output
    let _depth_uv = clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0));
    let _depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, _depth_uv, 0.0).r;
    let outDepth = mix(_depth, 0.2 + trailDensity * 0.6, coverage);

    textureStore(writeTexture, coords, finalColor);
    textureStore(writeDepthTexture, coords, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coords, finalColor);
}
