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

// Particle tracing along field line
fn traceFieldLine(start: vec2<f32>, fieldFn: fn(vec2<f32>) -> vec2<f32>, steps: i32) -> f32 {
    var pos = start;
    var totalField = 0.0;
    
    for (var i: i32 = 0; i < steps; i++) {
        let f = fieldFn(pos);
        let fLen = length(f);
        totalField += fLen;
        
        // Euler integration along field line
        pos = pos + normalize(f) * 0.01;
        
        if (fLen < 0.001) { break; }
    }
    
    return totalField;
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
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let t = u.config.x;
    
    // Parameters - safe randomization
    let fieldStrength = mix(0.3, 2.0, u.zoom_params.x);
    let particleSpeed = mix(0.2, 2.0, u.zoom_params.y);
    let numDipoles = i32(mix(1.0, 5.0, u.zoom_params.z));
    let trailLength = mix(0.3, 0.95, u.zoom_params.w);
    
    // Aspect correction
    let aspect = resolution.x / resolution.y;
    let p = (uv - 0.5) * vec2<f32>(aspect, 1.0) * 2.0;
    
    // Calculate total field
    var totalField = vec2<f32>(0.0);
    var col = vec3<f32>(0.0);
    
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
        
        // Draw field lines
        let numLines = 20;
        var minDist = 1000.0;
        
        for (var l: i32 = 0; l < numLines; l++) {
            let lineT = f32(l) / f32(numLines);
            
            // Multiple radii for each line
            for (var r: i32 = 1; r <= 5; r++) {
                let radius = f32(r) * 0.15;
                let particleT = t * particleSpeed + lineT * 6.28318;
                let pos = particleOnFieldLine(particleT, dipolePos, moment, radius);
                
                let dist = length(p - pos);
                minDist = smin(minDist, dist, 0.1);
            }
        }
        
        // Field line color
        let isNorth = d % 2 == 0;
        let fieldCol = fieldColor(0.5, isNorth);
        let lineThickness = 0.003;
        let lineIntensity = smoothstep(lineThickness * 3.0, 0.0, minDist);
        let lineCore = smoothstep(lineThickness, 0.0, minDist);
        
        col += fieldCol * lineIntensity + vec3<f32>(1.0) * lineCore * 0.3;
        
        // Draw dipole itself
        let dipoleDist = length(p - dipolePos);
        let dipoleSize = 0.03;
        let dipoleMask = smoothstep(dipoleSize, 0.0, dipoleDist);
        col = mix(col, fieldColor(1.0, isNorth), dipoleMask);
    }
    
    // Particles flowing along combined field
    let numParticles = 30;
    for (var i: i32 = 0; i < numParticles; i++) {
        let fi = f32(i);
        let particleT = t * particleSpeed + fi * 0.2;
        
        // Start at random position
        let startAngle = fi * 0.5;
        let startDist = 0.1 + hash21(vec2<f32>(fi, 0.0)) * 0.5;
        var particlePos = vec2<f32>(cos(startAngle), sin(startAngle)) * startDist;
        
        // Trace along field
        let traceSteps = i32(10.0 + fi * 0.5);
        for (var s: i32 = 0; s < traceSteps; s++) {
            let dist = length(p - particlePos);
            if (dist < 0.02) {
                let intensity = 1.0 - f32(s) / f32(traceSteps);
                col += vec3<f32>(1.0, 0.95, 0.8) * intensity * 0.5;
            }
            
            // Move along field
            var localField = vec2<f32>(0.0);
            for (var d: i32 = 0; d < numDipoles; d++) {
                let fd = f32(d);
                let angle = fd * 1.256 + t * 0.05;
                let dist2 = 0.3 + sin(t * 0.1 + fd) * 0.1;
                let dipolePos = vec2<f32>(cos(angle), sin(angle)) * dist2;
                let momentAngle = t * 0.2 + fd * 0.5;
                let moment = vec2<f32>(cos(momentAngle), sin(momentAngle));
                localField = localField + dipoleField(particlePos, dipolePos, moment, fieldStrength);
            }
            
            particlePos = particlePos + normalize(localField) * 0.02;
        }
    }
    
    // Field strength visualization (subtle background)
    let fieldMag = length(totalField);
    let bgCol = vec3<f32>(0.05, 0.05, 0.1) * (1.0 + fieldMag * 0.1);
    col = col + bgCol * (1.0 - saturate(length(col)));
    
    // Trails from previous frame
    let prev = textureLoad(dataTextureC, global_id.xy, 0).rgb;
    col = max(col, prev * trailLength);
    
    // Vignette
    let vignette = 1.0 - length(uv - 0.5) * 0.5;
    col *= vignette;
    
    textureStore(dataTextureA, global_id.xy, vec4<f32>(col * 0.95, 1.0));
    textureStore(writeTexture, global_id.xy, vec4<f32>(col, 1.0));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(fieldMag * 0.1, 0.0, 0.0, 0.0));
}
