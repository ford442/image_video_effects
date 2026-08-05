// ----------------------------------------------------------------
// Raptor Mini - Territorial Predator Simulation
// Category: generative
// Upgrade (batch 35 / Interactivist): sprung mouse pack-leader,
// velocity-aware pursuit, real bass/mids/treble + FFT reactivity,
// click strike shockwaves, emergent scent-memory feedback trails,
// generated relief depth.
// ----------------------------------------------------------------
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

fn hash21(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += vec3<f32>(dot(p3, p3.yzx + vec3<f32>(33.33)));
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var freq = 1.0;
    var pp = p;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        value += amplitude * fract(sin(dot(pp * freq, vec2<f32>(12.9898, 78.233))) * 43758.5453);
        pp = pp * 2.0 + vec2<f32>(1.7, 3.2);
        amplitude *= 0.5;
    }
    return value;
}

fn sdCapsule(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>, r: f32) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

fn voronoi(uv: vec2<f32>, t: f32) -> vec2<f32> {
    let n = floor(uv);
    let f = fract(uv);
    var minDist = 100.0;
    var cellId = 0.0;
    for (var j: i32 = -1; j <= 1; j = j + 1) {
        for (var i: i32 = -1; i <= 1; i = i + 1) {
            let g = vec2<f32>(f32(i), f32(j));
            let o = hash21(n + g);
            let anim = vec2<f32>(cos(t + o.x * 6.2831853), sin(t + o.y * 6.2831853)) * 0.3;
            let r = g + anim - f;
            let d = dot(r, r);
            if (d < minDist) {
                minDist = d;
                cellId = o.x;
            }
        }
    }
    return vec2<f32>(sqrt(minDist), cellId);
}

fn accumulateScent(uv: vec2<f32>, raptorPos: vec2<f32>, strength: f32) -> f32 {
    let d = length(uv - raptorPos);
    let trail = exp(-d * 12.0) * strength;
    let windDrift = sin(uv.x * 4.0 + uv.y * 3.0) * 0.1;
    let temporalDecay = exp(-length(uv - raptorPos * 0.5 + windDrift) * 0.5);
    return trail * temporalDecay;
}

fn grayScottRD(uv: vec2<f32>, feed: f32, kill: f32) -> vec2<f32> {
    let uChem = fbm(uv * 3.0, 2);
    let vChem = fbm(uv * 3.0 + vec2<f32>(5.2, 1.3), 2);
    let n1 = fbm(uv + vec2<f32>(0.01, 0.0), 3);
    let n2 = fbm(uv + vec2<f32>(0.0, 0.01), 3);
    let n3 = fbm(uv - vec2<f32>(0.01, 0.0), 3);
    let n4 = fbm(uv - vec2<f32>(0.0, 0.01), 3);
    let laplacian = (n1 + n2 + n3 + n4) * 0.25 - fbm(uv, 3);
    let reaction = uChem * vChem * vChem;
    let du = 0.2 * laplacian - reaction + feed * (1.0 - uChem);
    let dv = 0.1 * laplacian + reaction - (feed + kill) * vChem;
    return vec2<f32>(clamp(du + uChem, 0.0, 1.0), clamp(dv + vChem, 0.0, 1.0));
}

fn pursuitVector(predator: vec2<f32>, prey: vec2<f32>, speed: f32) -> vec2<f32> {
    let diff = prey - predator;
    let dist = length(diff);
    let dir = diff / max(dist, 0.001);
    return dir * speed * (1.0 + 1.0 / max(dist, 0.1));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    let coords = vec2<i32>(global_id.xy);
    if (global_id.x >= dims.x || global_id.y >= dims.y) { return; }

    let resF = vec2<f32>(dims);
    let aspect = f32(dims.x) / f32(dims.y);
    let uv = (vec2<f32>(coords) - 0.5 * resF) / f32(dims.y);
    let uv01 = (vec2<f32>(coords) + 0.5) / resF;
    let time = u.config.x;

    // --- Audio: real bands + guarded FFT bins only ---
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    var fftLow = 0.0;
    var fftHigh = 0.0;
    if (arrayLength(&extraBuffer) > 13u) {
        fftLow = extraBuffer[6];   // engine FFT bin 1
        fftHigh = extraBuffer[12]; // engine FFT bin 7
    }
    let rage = bass * 3.0;

    // --- Spring-smoothed pack leader (persistent state in extraBuffer[133..138]) ---
    let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    var smMouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    var smVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[137] < 0.5) { smMouse = rawMouse; smVel = vec2<f32>(0.0); }
    let sdt = select(0.016, clamp(time - extraBuffer[138], 0.001, 0.05), extraBuffer[137] > 0.5);
    let omega = 10.0 + mids * 4.0; // mids stiffen the spring: sharper follow
    smVel += ((rawMouse - smMouse) * omega * omega - smVel * 2.0 * omega) * sdt;
    smMouse += smVel * sdt;
    if (global_id.x == 0u && global_id.y == 0u && arrayLength(&extraBuffer) > 138u) {
        extraBuffer[133] = smMouse.x; extraBuffer[134] = smMouse.y;
        extraBuffer[135] = smVel.x; extraBuffer[136] = smVel.y;
        extraBuffer[137] = 1.0; extraBuffer[138] = time;
    }
    let mouse = (smMouse * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);
    let velMag = clamp(length(smVel) * 0.4, 0.0, 1.5);

    let turnSpeed = u.zoom_params.x;
    let maxSpeed = u.zoom_params.y;
    let rageDuration = u.zoom_params.z;
    let glowRadius = u.zoom_params.w;

    // --- Click strikes: guarded ripple shockwaves + held-press pounce ---
    var strike = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rippleAge = time - ripple.z;
        if (rippleAge >= 0.0 && rippleAge < 1.6) {
            let delta = (uv01 - ripple.xy) * vec2<f32>(aspect, 1.0);
            let ring = exp(-abs(length(delta) - rippleAge * 0.45) * 30.0) * exp(-rippleAge * 2.2);
            strike = max(strike, ring);
        }
    }
    let press = step(0.5, u.zoom_config.w);
    strike = max(strike, press * exp(-length(uv - mouse) * 6.0) * 0.6);

    let scalePattern = 4.0;
    var st = uv * scalePattern * 5.0;

    let baseDir = normalize(uv + vec2<f32>(0.001, 0.001));
    let targetDir = normalize(mouse - uv + vec2<f32>(0.001, 0.001));
    // velocity-aware: a fast pointer whips the pack around harder
    let turnBoost = clamp(velMag * 0.4, 0.0, 1.0);
    let dirToMouse = normalize(mix(baseDir, targetDir, clamp(turnSpeed + turnBoost * 0.35, 0.05, 1.0)) + vec2<f32>(0.0001));

    st += dirToMouse * time * maxSpeed * (1.0 + mids * 0.25);

    let voro = voronoi(st + vec2<f32>(time * 0.1, time * 0.15), time);
    let territoryBoundary = smoothstep(0.08, 0.0, voro.x);

    let id = floor(st);
    let f = fract(st) - 0.5;
    let rng = hash21(id);

    let raptorPos = f + dirToMouse * time * maxSpeed * 0.1;
    let scent = accumulateScent(uv, raptorPos, 0.5 + rage * 0.3);

    // mids feed the reaction-diffusion morph speed
    let gs = grayScottRD(uv * 2.0 + time * 0.1, 0.037 + mids * 0.006, 0.06 + rage * 0.01);
    let rdEnergy = gs.x;

    let bodyRadius = 0.2 * (1.0 + rage * 0.5);
    let capsuleA = vec2<f32>(-0.15, 0.0);
    let capsuleB = vec2<f32>(0.15, 0.0);
    let capsuleDist = sdCapsule(f, capsuleA, capsuleB, bodyRadius * 0.6);

    let pursuit = pursuitVector(uv, mouse, maxSpeed);
    let chaseIntensity = smoothstep(0.5, 0.0, length(pursuit) * 0.1) * (1.0 + velMag * 0.5);
    let pursuitAngle = atan2(targetDir.y, targetDir.x);
    let preyField = sin(f.x * 6.0 + pursuitAngle) * cos(f.y * 6.0 - pursuitAngle) * 0.5 + 0.5;

    // treble: claw sparkle detail on the body
    let sparkle = treble * smoothstep(0.72, 1.0, hash21(floor(st * 3.0) + vec2<f32>(floor(time * 8.0))).x);

    var territorialIntensity = 0.0;
    var energy = 0.0;
    var age = 0.0;
    var reproCooldown = 0.0;

    if (capsuleDist < 0.0) {
        territorialIntensity = 0.6 + rage * 0.4 + rng.x * 0.3 + preyField * 0.2 + chaseIntensity * 0.3 + strike * 0.5;
        energy = 0.8 + scent * 0.5 + rdEnergy * 0.3 + chaseIntensity * 0.4 + sparkle * 0.6;
        age = fract(time * 0.05 + rng.y * 10.0);
        reproCooldown = 1.0;
    } else {
        let glow = smoothstep(glowRadius * 0.6, 0.0, capsuleDist);
        let trailDecay = exp(-length(uv - mouse) * 2.0);
        territorialIntensity = territoryBoundary * 0.4 + glow * 0.2 + trailDecay * 0.1 + chaseIntensity * 0.15 + strike * 0.35;
        energy = scent * 0.6 + rdEnergy * 0.4 + glow * 0.3 + chaseIntensity * 0.2 + strike * 0.3;
        age = fract(length(uv) * 2.0 + time * 0.02);
        reproCooldown = glow * 0.35 + scent * 0.2 + trailDecay * 0.15;
    }

    var col = vec3<f32>(0.0);
    col.r = territorialIntensity * (0.8 + rage * 0.5) + fftLow * 0.15 * territorialIntensity;
    col.g = energy * 0.7 + scent * 0.4;
    col.b = age * 0.3 + rdEnergy * 0.15 + fftHigh * 0.2 * energy + sparkle * 0.4;

    let scaleTex = fract(length(f * rageDuration * 10.0));
    col *= 0.7 + 0.3 * scaleTex;

    // --- Emergent scent-memory: history-dependent feedback trails ---
    // Fast pointer + rage lengthen persistence; a strike wipes the local memory.
    let prev = textureLoad(dataTextureC, coords, 0);
    let trailZone = smoothstep(0.0, 0.25, capsuleDist);
    let persistence = clamp(0.5 + rage * 0.06 + velMag * 0.2, 0.0, 0.92) * trailZone * (1.0 - clamp(strike, 0.0, 1.0));
    col = mix(col, prev.rgb * vec3<f32>(0.965, 0.94, 0.92), persistence);

    let alpha = clamp(reproCooldown + strike * 0.25 + persistence * 0.3, 0.05, 0.95);
    let outColor = vec4<f32>(col, alpha);

    // Generated relief depth: body near (1), territory mid, open field far (0)
    let relief = clamp(1.0 - capsuleDist * 2.0, 0.0, 1.0);
    let depth = clamp(relief * 0.8 + territoryBoundary * 0.25 + strike * 0.3, 0.0, 1.0);

    textureStore(writeTexture, coords, outColor);
    textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coords, outColor);
}
