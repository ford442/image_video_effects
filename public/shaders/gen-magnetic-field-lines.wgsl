// ═══════════════════════════════════════════════════════════════════
//  Magnetic Field Lines - Dipole field visualization
//  Category: generative
//  Features: procedural, dipole equations, particle tracing
//  Created: 2026-03-22
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
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
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    
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
    let mouseField = dipoleField(p, mousePos, mouseMoment, fieldStrength * (0.28 + u.zoom_config.w * 0.72));
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
    
    // Field-advected, bounded auroral history.
    let fieldDir = totalField / max(length(totalField), 0.001);
    let historyVelocity = fieldDir * (2.0 + particleSpeed * 2.5 + bass * 2.0);
    let coord = vec2<i32>(global_id.xy);
    let maxCoord = vec2<i32>(max(i32(resolution.x) - 1, 0), max(i32(resolution.y) - 1, 0));
    let historyCoord = clamp(coord - vec2<i32>(historyVelocity), vec2<i32>(0), maxCoord);
    let history = textureLoad(dataTextureC, historyCoord, 0).rgb;
    col = clamp(col + history * clamp(trailLength * 0.42, 0.16, 0.4), vec3<f32>(0.0), vec3<f32>(5.0));
    
    // Vignette
    let vignette = 1.0 - length(uv - 0.5) * 0.5;
    col *= vignette;
    
    let alpha = clamp(lineEnergy * 0.7 + particleEnergy * 0.5 + mouseHalo * 0.3 + cmePulse * 0.32, 0.03, 0.97);
    let depth = clamp(lineEnergy * 0.48 + particleEnergy * 0.35 + fieldMag * 0.025, 0.0, 1.0);
    textureStore(dataTextureA, coord, vec4<f32>(col, alpha));
    textureStore(writeTexture, coord, vec4<f32>(acesToneMap(col * 1.15), alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
