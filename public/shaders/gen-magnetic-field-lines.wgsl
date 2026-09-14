// ═══════════════════════════════════════════════════════════════════
//  Magnetic Field Lines
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-14
//  Ideas: iron-filing line-integral convolution along B with chain length ∝ |B|; reconnection X-point null flash with separatrix arms
//  A packing: ACES display RGBA in A
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
  config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // .x = Field Strength, .y = Particle Speed, .z = Number of Dipoles, .w = Trail Length
  ripples: array<vec4<f32>, 50>,
};

// Magnetic dipole field: B ∝ (3(m·r)r - m) / |r|³
fn dipoleField(p: vec2<f32>, dipolePos: vec2<f32>, moment: vec2<f32>, strength: f32) -> vec2<f32> {
    let r = p - dipolePos;
    let rLen = length(r);
    let rLen3 = rLen * rLen * rLen + 0.001; // avoid division by zero
    
    let mDotR = dot(moment, r);
    let term1 = 3.0 * mDotR * r / (rLen3 * rLen);
    let term2 = moment / rLen3;
    
    return (term1 - term2) * strength;
}

// Field magnitude
fn fieldMagnitude(field: vec2<f32>) -> f32 {
    return length(field);
}

// Distance to field line (simplified)
fn distToFieldLine(uv: vec2<f32>, dipolePos: vec2<f32>, moment: vec2<f32>) -> f32 {
    let r = uv - dipolePos;
    let rLen = length(r);
    let angle = atan2(r.y, r.x);
    let momentAngle = atan2(moment.y, moment.x);
    
    // Simplified dipole field line equation in polar coords
    // r = sin²(θ) for a dipole
    let fieldAngle = angle - momentAngle;
    let expectedR = sin(fieldAngle) * sin(fieldAngle);
    
    return abs(rLen - expectedR * 0.5);
}

// Particle position along field line
fn particleOnFieldLine(t: f32, dipolePos: vec2<f32>, moment: vec2<f32>, radius: f32) -> vec2<f32> {
    let angle = t * 6.28318;
    let r = radius * sin(angle) * sin(angle);
    
    let momentAngle = atan2(moment.y, moment.x);
    let worldAngle = angle + momentAngle;
    
    return dipolePos + vec2<f32>(cos(worldAngle), sin(worldAngle)) * r;
}

// Color based on field strength
fn fieldColor(strength: f32, isNorth: bool) -> vec3<f32> {
    if (isNorth) {
        // North pole: blue shades
        return mix(vec3<f32>(0.2, 0.3, 0.8), vec3<f32>(0.5, 0.7, 1.0), strength);
    } else {
        // South pole: red shades
        return mix(vec3<f32>(0.8, 0.2, 0.2), vec3<f32>(1.0, 0.5, 0.5), strength);
    }
}

// Smooth minimum for field lines
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * (1.0 / 4.0);
}


// Hash function for randomness
fn hash21(p: vec2<f32>) -> f32 {
    let k = vec3<f32>(0.3183099, 0.3678794, 0.1031);
    let x = p.x * k.x + p.y * k.y;
    return fract(sin(x) * 43758.5453);
}

fn sdSegment(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.000001), 0.0, 1.0);
    return length(pa - ba * h);
}

fn hash22(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

// Smooth value noise — the "iron dust" substrate that the LIC chains up
fn dustNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let w = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash22(i), hash22(i + vec2<f32>(1.0, 0.0)), w.x),
               mix(hash22(i + vec2<f32>(0.0, 1.0)), hash22(i + vec2<f32>(1.0, 1.0)), w.x), w.y);
}

// Total B at p — the same orbiting dipole family + mouse source as main().
// xy = field, z = distance to the nearest source (to reject core singularities).
fn totalFieldAt(p: vec2<f32>, t: f32, numDipoles: i32, fieldStrength: f32, mousePos: vec2<f32>, mouseStrength: f32) -> vec3<f32> {
    var B = vec2<f32>(0.0);
    var nearest = length(p - mousePos);
    for (var d: i32 = 0; d < numDipoles; d++) {
        let fd = f32(d);
        let angle = fd * 1.256 + t * 0.05;
        let dist = 0.3 + sin(t * 0.1 + fd) * 0.1;
        let dipolePos = vec2<f32>(cos(angle), sin(angle)) * dist;
        let momentAngle = t * 0.2 + fd * 0.5;
        B += dipoleField(p, dipolePos, vec2<f32>(cos(momentAngle), sin(momentAngle)), fieldStrength);
        nearest = min(nearest, length(p - dipolePos));
    }
    let mouseMoment = vec2<f32>(cos(t * 0.7), sin(t * 0.7));
    B += dipoleField(p, mousePos, mouseMoment, mouseStrength);
    return vec3<f32>(B, nearest);
}

// ── IDEA 1: iron-filing line-integral convolution ──
// Iron dust is convolved along the local streamline of B (RK1 steps both ways),
// so grains chain into filaments exactly as filings do on paper. The chain
// length grows with log|B|: long, combed chains near the poles, loose short
// grains in weak-field gaps.
fn ironFilingLIC(p: vec2<f32>, B0: vec2<f32>, t: f32, numDipoles: i32, fieldStrength: f32, mousePos: vec2<f32>, mouseStrength: f32, trail: f32, jitter: f32) -> f32 {
    let mag = length(B0);
    let chainLen = clamp(0.012 + log(1.0 + mag) * 0.016, 0.012, 0.11) * (0.55 + trail * 0.7);
    let steps = 6;
    let h = chainLen / f32(steps);
    let grain = 190.0;
    var acc = dustNoise(p * grain + jitter);
    var wsum = 1.0;
    var qf = p;
    var qb = p;
    var df = B0 / max(mag, 0.0001);
    var db = df;
    for (var k: i32 = 0; k < steps; k++) {
        qf += df * h;
        qb -= db * h;
        let wk = 1.0 - f32(k) / f32(steps + 1);  // tent kernel
        acc += (dustNoise(qf * grain + jitter) + dustNoise(qb * grain + jitter)) * wk;
        wsum += 2.0 * wk;
        let bf = totalFieldAt(qf, t, numDipoles, fieldStrength, mousePos, mouseStrength).xy;
        let bb = totalFieldAt(qb, t, numDipoles, fieldStrength, mousePos, mouseStrength).xy;
        df = bf / max(length(bf), 0.0001);
        db = bb / max(length(bb), 0.0001);
    }
    return acc / wsum;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let t = u.config.x;
    
    // Parameters - safe randomization
    let fieldStrength = mix(0.3, 2.0, u.zoom_params.x);
    let particleSpeed = mix(0.2, 2.0, u.zoom_params.y);
    let numDipoles = i32(mix(1.0, 5.0, u.zoom_params.z));
    let trailLength = mix(0.3, 0.95, u.zoom_params.w);
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
    
    // Aspect correction
    let aspect = resolution.x / resolution.y;
    let p = (uv - 0.5) * vec2<f32>(aspect, 1.0) * 2.0;
    
    let mousePos = (u.zoom_config.yz - 0.5) * vec2<f32>(aspect, 1.0) * 2.0;

    // Calculate total field and render a compact analytic family of field
    // lines. This replaces the former 20x5 samples for every dipole.
    var totalField = vec2<f32>(0.0);
    var col = vec3<f32>(0.0);
    var lineEnergy = 0.0;
    
    for (var d: i32 = 0; d < numDipoles; d++) {
        let fd = f32(d);
        
        // Dipole position
        let angle = fd * 1.256 + t * 0.05;
        let dist = 0.3 + sin(t * 0.1 + fd) * 0.1;
        let dipolePos = vec2<f32>(cos(angle), sin(angle)) * dist;
        
        // Dipole moment (orientation)
        let momentAngle = t * 0.2 + fd * 0.5;
        let moment = vec2<f32>(cos(momentAngle), sin(momentAngle));
        
        // Calculate field
        let field = dipoleField(p, dipolePos, moment, fieldStrength);
        totalField = totalField + field;
        
        let relative = p - dipolePos;
        let polarAngle = atan2(relative.y, relative.x) - momentAngle;
        let polarRadius = length(relative);
        let angularShape = sin(polarAngle) * sin(polarAngle);
        var minDist = 1000.0;
        for (var shell: i32 = 1; shell <= 6; shell++) {
            let shellRadius = f32(shell) * 0.14;
            let expectedRadius = shellRadius * angularShape;
            minDist = min(minDist, abs(polarRadius - expectedRadius));
        }
        
        // Field line color
        let isNorth = d % 2 == 0;
        let fieldCol = fieldColor(0.5, isNorth);
        let lineThickness = 0.0035 + treble * 0.0015;
        let lineIntensity = smoothstep(lineThickness * 3.0, 0.0, minDist);
        let lineCore = smoothstep(lineThickness, 0.0, minDist);
        let spectralFlow = 0.6 + 0.4 * sin(polarAngle * 9.0 - t * (4.0 + particleSpeed * 3.0) + fd);
        col += fieldCol * lineIntensity * (0.55 + spectralFlow * (0.45 + mids * 0.35)) +
               vec3<f32>(1.0) * lineCore * (0.22 + treble * 0.22);
        lineEnergy = max(lineEnergy, lineIntensity);
        
        // Draw dipole itself
        let dipoleDist = length(p - dipolePos);
        let dipoleSize = 0.03;
        let dipoleMask = smoothstep(dipoleSize, 0.0, dipoleDist);
        col = mix(col, fieldColor(1.0, isNorth), dipoleMask);
    }

    // The cursor becomes a live auxiliary magnetic source. Top-down mouse Y
    // maps directly into the same aspect-correct field space.
    let mouseMoment = normalize(vec2<f32>(cos(t * 0.7), sin(t * 0.7)));
    let mouseStrength = fieldStrength * (0.28 + u.zoom_config.w * 0.72);
    let mouseField = dipoleField(p, mousePos, mouseMoment, mouseStrength);
    totalField += mouseField;
    let mouseHalo = exp(-length(p - mousePos) * 9.0) * (0.25 + bass * 0.65);
    col += vec3<f32>(0.25, 0.8, 1.35) * mouseHalo;

    // Eighteen analytic charged-particle segments replace the prior nested
    // per-particle field integrator while preserving visible field motion.
    let numParticles = 18;
    var particleEnergy = 0.0;
    for (var i: i32 = 0; i < numParticles; i++) {
        let fi = f32(i);
        let dipoleIndex = i % numDipoles;
        let fd = f32(dipoleIndex);
        let orbitAngle = fd * 1.256 + t * 0.05;
        let orbitDistance = 0.3 + sin(t * 0.1 + fd) * 0.1;
        let dipolePos = vec2<f32>(cos(orbitAngle), sin(orbitAngle)) * orbitDistance;
        let momentAngle = t * 0.2 + fd * 0.5;
        let moment = vec2<f32>(cos(momentAngle), sin(momentAngle));
        let radius = 0.16 + hash21(vec2<f32>(fi, 3.7)) * 0.58;
        let phase = fract(t * particleSpeed * (0.16 + bass * 0.08) + fi * 0.117);
        let particlePos = particleOnFieldLine(phase, dipolePos, moment, radius);
        let flow = dipoleField(particlePos, dipolePos, moment, fieldStrength);
        let flowDir = flow / max(length(flow), 0.001);
        let streakLength = 0.035 + particleSpeed * 0.035 + bass * 0.035;
        let streakDistance = sdSegment(p, particlePos - flowDir * streakLength, particlePos + flowDir * 0.012);
        let streak = exp(-streakDistance * streakDistance * 9000.0) * (0.45 + treble * 0.75);
        col += mix(vec3<f32>(1.0, 0.45, 0.18), vec3<f32>(0.25, 0.8, 1.4), fract(fi * 0.37)) * streak;
        particleEnergy = max(particleEnergy, streak);
    }

    // Clicks emit fast coronal-mass wavefronts through the magnetosphere.
    var cmePulse = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = t - ripple.z;
        if (age >= 0.0 && age < 1.5) {
            let delta = (uv - ripple.xy) * vec2<f32>(aspect, 1.0) * 2.0;
            cmePulse = max(cmePulse, exp(-abs(length(delta) - age * 0.75) * 58.0) * exp(-age * 1.7));
        }
    }
    col += vec3<f32>(0.55, 0.3, 1.25) * cmePulse * (0.65 + bass * 0.8);
    
    // Field strength visualization (subtle background)
    let fieldMag = length(totalField);
    let bgCol = vec3<f32>(0.05, 0.05, 0.1) * (1.0 + fieldMag * 0.1);
    col = col + bgCol * (1.0 - clamp(length(col), 0.0, 1.0));
    
    // ── IDEA 1: iron filings chained along B ──
    let lic = ironFilingLIC(p, totalField, t, numDipoles, fieldStrength, mousePos, mouseStrength, trailLength, 0.0);
    let filings = smoothstep(0.5, 0.78, lic) * clamp(log(1.0 + fieldMag) * 0.35, 0.0, 1.0);
    col += vec3<f32>(0.42, 0.46, 0.55) * filings * (0.35 + mids * 0.25);

    // ── IDEA 2: magnetic reconnection X-point flash ──
    // Newton step to the nearest null: δ = −J⁻¹B. Where opposing fields (the
    // mouse source vs. the orbiting dipoles) cancel, det J < 0 marks an X-type
    // saddle. A hot core flashes at the null and light runs along the two
    // separatrices (eigen-directions of the symmetric Jacobian).
    let jh = 0.004;
    let Bx = totalFieldAt(p + vec2<f32>(jh, 0.0), t, numDipoles, fieldStrength, mousePos, mouseStrength);
    let By = totalFieldAt(p + vec2<f32>(0.0, jh), t, numDipoles, fieldStrength, mousePos, mouseStrength);
    let B0n = totalFieldAt(p, t, numDipoles, fieldStrength, mousePos, mouseStrength);
    let ja = (Bx.x - B0n.x) / jh;
    let jb = (By.x - B0n.x) / jh;
    let jc = (Bx.y - B0n.y) / jh;
    let jd = (By.y - B0n.y) / jh;
    let detJ = ja * jd - jb * jc;
    let safeDet = select(-1e-6, detJ, abs(detJ) > 1e-6);
    let delta = -vec2<f32>(jd * B0n.x - jb * B0n.y, -jc * B0n.x + ja * B0n.y) / safeDet;
    let deltaLen = length(delta);
    let isSaddle = select(0.0, 1.0, detJ < 0.0);
    let clearOfCores = smoothstep(0.25, 0.1, deltaLen / max(B0n.z, 0.001));
    let sepAngle = 0.5 * atan2(0.5 * (jb + jc), 0.5 * (ja - jd));
    let e1 = vec2<f32>(cos(sepAngle), sin(sepAngle));
    let e2 = vec2<f32>(-e1.y, e1.x);
    let armDist = min(abs(dot(delta, e1)), abs(dot(delta, e2)));
    let reconnectRate = 0.55 + 0.45 * sin(t * (3.0 + particleSpeed * 2.0 + treble * 5.0));
    let xGate = isSaddle * clearOfCores * (0.35 + u.zoom_config.w * 0.9 + bass * 0.5) * reconnectRate;
    let xCore = exp(-deltaLen * deltaLen * 1400.0);
    let xArms = exp(-armDist * armDist * 26000.0) * exp(-deltaLen * 11.0);
    let xFlash = clamp(xGate * (xCore + xArms * 0.6), 0.0, 3.0);
    col += (vec3<f32>(1.3, 0.75, 1.5) * xCore + vec3<f32>(0.6, 1.1, 1.4) * xArms * 0.6) * xGate;

    // Field-advected, bounded auroral history.
    let fieldDir = totalField / max(length(totalField), 0.001);
    let historyVelocity = fieldDir * (2.0 + particleSpeed * 2.5 + bass * 2.0);
    let coord = vec2<i32>(global_id.xy);
    let maxCoord = vec2<i32>(max(i32(resolution.x) - 1, 0), max(i32(resolution.y) - 1, 0));
    let historyCoord = clamp(coord - vec2<i32>(historyVelocity), vec2<i32>(0), maxCoord);
    let history = textureLoad(dataTextureC, historyCoord, 0).rgb;  // display-space (ACES) history from A
    col = clamp(col + history * clamp(trailLength * 0.42, 0.16, 0.4), vec3<f32>(0.0), vec3<f32>(5.0));
    
    // Vignette
    let vignette = 1.0 - length(uv - 0.5) * 0.5;
    col *= vignette;
    
    let alpha = clamp(lineEnergy * 0.7 + particleEnergy * 0.5 + mouseHalo * 0.3 + cmePulse * 0.32 + filings * 0.25 + xFlash * 0.4, 0.03, 0.97);
    let depth = clamp(lineEnergy * 0.48 + particleEnergy * 0.35 + fieldMag * 0.025 + filings * 0.1 + xFlash * 0.2, 0.0, 1.0);
    let finalColor = vec4<f32>(acesToneMap(col * (1.15 + bass * 0.2)), alpha);
    textureStore(writeTexture, coord, finalColor);
    textureStore(dataTextureA, coord, finalColor);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
