// ═══════════════════════════════════════════════════════════════════
//  Holographic Flicker
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive, temporal-flicker,
//            depth-rainbow, chromatic-ghosting, interference-fringes,
//            scanline-jitter, temporal-rgb-offset, upgraded-rgba
//  Complexity: High
//  Chunks From: holographic-flicker, hash, bass_env
//  Created: 2024-01-01
//  Upgraded: 2026-06-28
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

// Math/SDF tools for continuous geometry
fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn sdfHexagon(p: vec2<f32>, r: f32) -> f32 {
    let k = vec3<f32>(-0.866025404, 0.5, 0.577350269);
    var p2 = abs(p);
    p2 = p2 - 2.0 * min(dot(k.xy, p2), 0.0) * k.xy;
    p2 = p2 - vec2<f32>(clamp(p2.x, -k.z * r, k.z * r), r);
    return length(p2) * sign(p2.y);
}

// ACES tone mapping
fn aces_tonemap(color: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return saturate((color * (a * color + b)) / (color * (c * color + d) + e));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    
    // Audio from plasmaBuffer (truthful three-band audio + bins)
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let bins = plasmaBuffer[1]; 
    
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;
    let mouseClick = u.config.y;
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let centeredUV = (uv - 0.5) * vec2<f32>(aspect, 1.0);
    
    let flickerSpeed = u.zoom_params.x;
    let glitchAmt = u.zoom_params.y;
    let hologramIntensity = u.zoom_params.z;
    let ghostAmt = u.zoom_params.w;
    
    // Single-writer persistent state logic for "held-pointer response" (Bounded spring)
    if (global_id.x == 0u && global_id.y == 0u) {
        var pointer_state = extraBuffer[133];
        var pointer_vel = extraBuffer[134];
        let target = mix(0.0, 1.0, step(0.5, mouseClick));
        
        let force = (target - pointer_state) * 0.1 - pointer_vel * 0.15;
        pointer_vel = clamp(pointer_vel + force, -0.5, 0.5);
        pointer_state = clamp(pointer_state + pointer_vel, 0.0, 1.0);
        
        extraBuffer[133] = pointer_state;
        extraBuffer[134] = pointer_vel;
    }
    
    let pointer_smooth = extraBuffer[133];

    // Bounded click ripples (capped fronts)
    var rippleEffect = 0.0;
    for (var i: i32 = 0; i < 5; i++) {
        let r = u.ripples[i];
        let rPos = r.xy;
        let rTime = r.z;
        if (rTime > 0.0 && rTime < 2.0) { 
            let dist = length((uv - rPos) * vec2<f32>(aspect, 1.0));
            let rAmp = smoothstep(2.0, 0.0, rTime);
            let wave = sin((dist - rTime * 0.5) * 40.0) * exp(-dist * 5.0) * rAmp;
            rippleEffect += wave * 0.5;
        }
    }
    
    // Continuous geometry background layer (intricate detail & fast motion)
    var geo = 0.0;
    var gUv = centeredUV * rot2D(time * 0.5 + pointer_smooth * 1.5) * (1.0 - rippleEffect * 0.1);
    for(var i=0.0; i<3.0; i+=1.0) {
        gUv = gUv * (1.5 + bass * 0.1);
        let d = sdfHexagon(gUv, 0.3 + 0.15 * sin(time * 2.0 + i + bins.x * 0.5));
        geo += smoothstep(0.02, 0.0, abs(d)) * (1.0 - i * 0.2);
    }
    
    // Scanline jitter and temporal offset
    let glitchLine = floor(uv.y * resolution.y + time * 100.0);
    let jitter = (hash21(vec2<f32>(glitchLine, time)) - 0.5) * glitchAmt * (mids + 0.1) * 0.1;
    let jitteredUV = uv + vec2<f32>(jitter, 0.0);
    
    let offset = (glitchAmt + ghostAmt) * 0.02 * (1.0 + treble * 0.5);
    
    let rRead = textureSampleLevel(readTexture, u_sampler, jitteredUV + vec2<f32>(offset, 0.0), 0.0).r;
    let gRead = textureSampleLevel(readTexture, u_sampler, jitteredUV, 0.0).g;
    let bRead = textureSampleLevel(readTexture, u_sampler, jitteredUV - vec2<f32>(offset, 0.0), 0.0).b;
    let aRead = textureSampleLevel(readTexture, u_sampler, jitteredUV, 0.0).a;
    let rgb = vec3<f32>(rRead, gRead, bRead);
    
    // Exact textureLoad for temporal chromatic ghosting from dataTextureC
    let prev = textureLoad(dataTextureC, vec2<i32>(global_id.xy), 0);
    let base_idx = vec2<i32>(global_id.xy);
    let res_idx = vec2<i32>(resolution) - 1;
    let shift = i32(ghostAmt * 10.0 + rippleEffect * 5.0);
    let r_idx = clamp(base_idx + vec2<i32>(shift, 0), vec2<i32>(0), res_idx);
    let b_idx = clamp(base_idx - vec2<i32>(shift, 0), vec2<i32>(0), res_idx);
    
    let rGhost = textureLoad(dataTextureC, r_idx, 0).r;
    let bGhost = textureLoad(dataTextureC, b_idx, 0).b;
    let ghostColor = vec3<f32>(rGhost, prev.g, bGhost) * ghostAmt * 0.9;
    
    // Prismatic / Hologram logic (psychedelic themes)
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthHue = mix(0.0, 1.0, depth);
    let k = vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0);
    let hue = fract(depthHue + time * 0.2 + bass * 0.2 + pointer_smooth * 0.1);
    let p = abs(fract(vec3<f32>(hue) + k) * 6.0 - vec3<f32>(3.0));
    let rainbow = clamp(p - vec3<f32>(1.0), vec3<f32>(0.0), vec3<f32>(1.0));
    
    // Audio-reactive flicker
    let flicker = hash21(vec2<f32>(floor(time * flickerSpeed * 30.0), uv.y));
    let blackout = step(1.0 - bass * 0.3, flicker) * 0.4 * (1.0 + glitchAmt);
    
    let luma = dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
    let geoColor = rainbow * geo * hologramIntensity * 1.5;
    
    var finalRGB = rgb + ghostColor + geoColor + (rainbow * rippleEffect * 0.8);
    finalRGB = mix(finalRGB, vec3<f32>(0.0), blackout);
    
    // ACES Tonemapping
    finalRGB = aces_tonemap(finalRGB);
    
    // Semantic alpha (meaningful based on content brightness, effects, and source)
    let alpha = saturate(aRead * 0.85 + luma * 0.2 + geo * 0.6 + rippleEffect * 0.3 + ghostAmt * 0.15);
    
    let outColor = vec4<f32>(finalRGB, alpha);
    
    // Output constraints: write to A and writeTexture, but not B
    textureStore(writeTexture, vec2<i32>(global_id.xy), outColor);
    textureStore(dataTextureA, vec2<i32>(global_id.xy), outColor);
    
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
