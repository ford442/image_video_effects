// ═══════════════════════════════════════════════════════════════════
//  Holographic Interferometry
//  Category: generative
//  Features: advanced-hybrid, interference-patterns, holography, phase-coloring
//  Complexity: High
//  Chunks From: holographic_interference.wgsl, anamorphic-flare
//  Created: 2026-03-22
//  By: Agent 3B - Advanced Hybrid Creator
// ═══════════════════════════════════════════════════════════════════
//  Simulated hologram with interference fringes
//  Rainbow interference patterns, speckled laser light, depth-parallax
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

// ACES Tone Map
fn aces_tonemap(color: vec3<f32>) -> vec3<f32> {
    let a = 2.51f;
    let b = 0.03f;
    let c = 2.43f;
    let d = 0.59f;
    let e = 0.14f;
    return clamp((color * (a * color + b)) / (color * (c * color + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ═══ SPECKLE NOISE (laser coherence) ═══
fn speckleNoise(uv: vec2<f32>, coherence: f32) -> f32 {
    let scale = mix(50.0, 500.0, coherence);
    var s = 0.0;
    for (var i = 0; i < 4; i++) {
        let fi = f32(i);
        s += hash12(uv * scale + vec2<f32>(fi * 13.7, fi * 42.3));
    }
    return s / 4.0;
}

// ═══ INTERFERENCE PATTERN ═══
fn interferencePattern(uv: vec2<f32>, depth: f32, fringeDensity: f32, angle: f32, distortion: f32) -> f32 {
    let objectPhase = depth * fringeDensity * 10.0 + distortion;
    let refPhase = (uv.x * cos(angle) + uv.y * sin(angle)) * fringeDensity * 50.0;
    let phaseDiff = objectPhase + refPhase;
    return 0.5 + 0.5 * cos(phaseDiff);
}

// ═══ HOLOGRAPHIC RECONSTRUCTION ═══
fn reconstructHologram(uv: vec2<f32>, depth: f32, intensity: f32, phase: f32, angle: f32) -> vec3<f32> {
    let reconPhase = (uv.x * cos(angle + 0.5) + uv.y * sin(angle + 0.5)) * 20.0;
    let totalPhase = phase + reconPhase;
    let hue = fract(totalPhase / 6.2831853);
    let sat = 0.7 + intensity * 0.3;
    let val = 0.5 + intensity * 0.5;
    
    let c = val * sat;
    let h = hue * 6.0;
    let x = c * (1.0 - abs(h % 2.0 - 1.0));
    var rgb = vec3<f32>(0.0);
    
    if (h < 1.0) { rgb = vec3<f32>(c, x, 0.0); }
    else if (h < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
    else if (h < 3.0) { rgb = vec3<f32>(0.0, c, x); }
    else if (h < 4.0) { rgb = vec3<f32>(0.0, x, c); }
    else if (h < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
    else { rgb = vec3<f32>(c, 0.0, x); }
    
    return rgb + vec3<f32>(val - c);
}

// Pointer physics
fn processPointerSpring(uv: vec2<f32>, res: vec2<f32>, isMaster: bool) -> vec2<f32> {
    if (isMaster) {
        let pointer = u.zoom_config.xy;
        let isDown = u.zoom_config.z > 0.5;
        let pUV = pointer / res;
        var pVel = vec2<f32>(0.0);
        let curP = vec2<f32>(extraBuffer[133], extraBuffer[134]);
        
        if (isDown) {
            let diff = pUV - curP;
            pVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
            pVel += diff * 0.15;
            pVel *= 0.85;
            let nP = curP + pVel;
            extraBuffer[135] = clamp(pVel.x, -0.05, 0.05);
            extraBuffer[136] = clamp(pVel.y, -0.05, 0.05);
            extraBuffer[133] = clamp(nP.x, 0.0, 1.0);
            extraBuffer[134] = clamp(nP.y, 0.0, 1.0);
        } else {
            extraBuffer[135] *= 0.9;
            extraBuffer[136] *= 0.9;
            extraBuffer[133] += extraBuffer[135];
            extraBuffer[134] += extraBuffer[136];
        }
        
        let curClick = extraBuffer[137];
        if (isDown && curClick < 0.5) {
            extraBuffer[138] = 1.0;
        }
        extraBuffer[137] = u.zoom_config.z;
        extraBuffer[138] *= 0.95;
    }
    workgroupBarrier();
    return vec2<f32>(extraBuffer[133], extraBuffer[134]);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let res = vec2<f32>(resolution);
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    
    let isMaster = global_id.x == 0u && global_id.y == 0u;
    let pPos = processPointerSpring(vec2<f32>(global_id.xy) / res, res, isMaster);
    let clickRipple = extraBuffer[138];
    
    let uv = vec2<f32>(global_id.xy) / res;
    let time = u.config.x;
    
    let bass = plasmaBuffer[0].x;
    let mid = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let bin20 = plasmaBuffer[20].x;
    
    let id = vec2<i32>(global_id.xy);
    
    let fringeDensity = mix(10.0, 100.0, u.zoom_params.x); // x: Fringe density
    let coherence = u.zoom_params.y;                        // y: Coherence (speckle size)
    let reconAngle = u.zoom_params.z * 3.14159265;         // z: Reconstruction angle
    let saturation = mix(0.5, 1.5, u.zoom_params.w);       // w: Saturation
    
    let pointerDist = distance(uv, pPos);
    let holdEffect = smoothstep(0.3, 0.0, pointerDist) * u.zoom_config.z;
    
    let sourceColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let depthSrc = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    
    let geo = sin(uv.x * 20.0 + time + bass) * cos(uv.y * 20.0 - time + mid) * 0.1;
    let depth = depthSrc + geo;
    let luma = dot(sourceColor, vec3<f32>(0.299, 0.587, 0.114));
    
    var rippleDistortion = 0.0;
    for (var i = 0u; i < 50u; i++) {
        let r = u.ripples[i];
        if (r.w > 0.0 && r.z > 0.0) {
            let rd = distance(uv, r.xy / res);
            let age = r.w * 3.0;
            let wave = sin(rd * 30.0 - age * 10.0) * exp(-rd * 10.0) * r.z;
            rippleDistortion += wave;
        }
    }
    rippleDistortion += sin(pointerDist * 40.0 - time * 10.0) * exp(-pointerDist * 15.0) * clickRipple;
    rippleDistortion += holdEffect * 0.2;
    
    let interference = interferencePattern(uv, depth, fringeDensity, reconAngle, rippleDistortion);
    let phase = acos(clamp(interference * 2.0 - 1.0, -1.0, 1.0));
    
    var holoColor = reconstructHologram(uv, depth, luma, phase, reconAngle);
    
    let speckle = speckleNoise(uv + time * 0.01 * (1.0 + treble), coherence);
    let specklePattern = mix(0.8, 1.2, speckle * coherence);
    
    let hologram = holoColor * (luma + bass * 0.2) * specklePattern * saturation;
    
    let fringes = sin(phase * fringeDensity + rippleDistortion * 5.0) * 0.5 + 0.5;
    let fringeColor = vec3<f32>(fringes * 0.5, fringes * 0.3, fringes * 0.7);
    
    let prev = textureLoad(dataTextureC, id, 0).rgb;
    
    var color = mix(sourceColor * 0.3, hologram + fringeColor * 0.2, 0.8);
    
    let parallax = depth * 0.02 + holdEffect * 0.05;
    let parallaxUV = uv + vec2<f32>(cos(reconAngle), sin(reconAngle)) * parallax;
    let parallaxColor = textureSampleLevel(readTexture, u_sampler, clamp(parallaxUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    
    color = mix(color, parallaxColor * holoColor, clamp(depth * 0.3 + holdEffect * 0.2, 0.0, 1.0));
    
    color = mix(prev, color, 0.8 + bin20 * 0.1);
    
    let final_color = aces_tonemap(color);
    let alpha = clamp(luma + clickRipple + holdEffect + interference * 0.2, 0.1, 1.0);
    
    textureStore(writeTexture, id, vec4<f32>(final_color, alpha));
    textureStore(dataTextureA, id, vec4<f32>(final_color, alpha));
    textureStore(writeDepthTexture, id, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
