// ═══════════════════════════════════════════════════════════════════
//  Heat Haze Volumetric
//  Category: advanced-hybrid
//  Features: heat-diffusion, volumetric-fog, refraction, depth-aware,
//            mouse-driven, temporal
//  Complexity: Very High
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

fn ACESFilm(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Volumetric density field
fn density(p: vec3<f32>, time: f32, audio: vec3<f32>, held: f32) -> f32 {
    var q = p;
    // Optical twist based on held spring and time
    let angle = q.y * 0.5 - time * 0.5;
    let ca = cos(angle);
    let sa = sin(angle);
    let oldX = q.x;
    q.x = oldX * ca - q.z * sa;
    q.z = oldX * sa + q.z * ca;

    // Three-band audio integration
    let bass = audio.x;
    let mid = audio.y;
    
    // Core thermal column
    let dColumn = length(q.xz) - (0.4 + bass * 0.3 + held * 0.5);
    
    // Gyroid-like continuous geometry
    let g = dot(sin(q * 3.0 - time * 1.2), cos(q.yzx * 3.0 + time * 0.8));
    
    let mask = smoothstep(1.5, 0.0, dColumn);
    
    return max(0.0, (mask + g * (0.3 + mid * 0.2)) * 1.5);
}

fn densityGrad(p: vec3<f32>, time: f32, audio: vec3<f32>, held: f32) -> vec3<f32> {
    let e = vec2<f32>(0.02, 0.0);
    return vec3<f32>(
        density(p + e.xyy, time, audio, held) - density(p - e.xyy, time, audio, held),
        density(p + e.yxy, time, audio, held) - density(p - e.yxy, time, audio, held),
        density(p + e.yyx, time, audio, held) - density(p - e.yyx, time, audio, held)
    );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let time = u.config.x;
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    // Single-writer bounded spring state
    if (gid.x == 0u && gid.y == 0u) {
        let dt = 0.016;
        let target = select(0.0, 1.0, mouseDown > 0.5);
        let pos = extraBuffer[133];
        let vel = extraBuffer[134];
        
        let force = (target - pos) * 150.0 - vel * 12.0; 
        let nVel = vel + force * dt;
        let nPos = clamp(pos + nVel * dt, -0.2, 1.2); 
        
        extraBuffer[133] = nPos;
        extraBuffer[134] = nVel;
    }
    
    let held = extraBuffer[133];

    // Preserve existing params exactly
    let heatGain = u.zoom_params.x;     
    let decayRate = u.zoom_params.y;    
    let fogDensity = mix(0.2, 3.0, u.zoom_params.z); 
    let refraction = u.zoom_params.w;   

    let bass = plasmaBuffer[0].x;
    let mid = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let audio = vec3<f32>(bass, mid, treble);

    let uv = vec2<f32>(gid.xy) / res;
    let aspect = res.x / res.y;
    
    // Capped click ripples
    var rippleNormal = vec2<f32>(0.0);
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let r = u.ripples[i];
        let d = distance(uv * vec2<f32>(aspect, 1.0), r.xy * vec2<f32>(aspect, 1.0));
        let age = time - r.z;
        if (age > 0.0 && age < 2.5) {
            let phase = d * 45.0 - age * 18.0;
            let env = smoothstep(0.0, 0.1, age) * smoothstep(2.5, 1.5, age) * smoothstep(0.5, 0.0, d);
            let dir = normalize(uv - r.xy);
            rippleNormal += dir * cos(phase) * env;
        }
    }

    let uv_c = (vec2<f32>(gid.xy) - 0.5 * res) / res.y;
    
    let ro = vec3<f32>(0.0, 0.0, -2.5 - held * 0.5);
    var rd = normalize(vec3<f32>(uv_c + rippleNormal * 0.15 * heatGain, 1.0));

    // Volumetric raymarching of the thermal field
    var transmittance = 1.0;
    var scatteredLight = vec3<f32>(0.0);
    let stepSize = 0.12;
    var tDist = 0.0;
    
    for (var i = 0; i < 35; i = i + 1) {
        let p = ro + rd * tDist;
        let dens = density(p, time, audio, held) * fogDensity;
        
        if (dens > 0.01) {
            let grad = densityGrad(p, time, audio, held);
            
            // Optical continuous refraction inside the heat volume
            rd = normalize(rd - grad * refraction * 0.08);
            
            let dt = stepSize;
            let t = exp(-dens * dt * (2.0 + decayRate * 2.0));
            
            let heatTemp = smoothstep(0.0, 1.2, dens) * heatGain;
            let emitBase = mix(vec3<f32>(0.05, 0.1, 0.4), vec3<f32>(1.0, 0.25, 0.05), heatTemp);
            
            // Prismatic hues
            let emitPrism = vec3<f32>(
                sin(dens * 5.0 + time) * 0.5 + 0.5,
                cos(dens * 6.0 + time * 1.1) * 0.5 + 0.5,
                sin(dens * 7.0 - time * 0.9) * 0.5 + 0.5
            );
            
            let emitCol = mix(emitBase, emitPrism, held * 0.5) * (1.0 + treble * 0.5);
            
            scatteredLight += transmittance * (1.0 - t) * emitCol * 2.0;
            transmittance *= t;
            
            if (transmittance < 0.01) { break; }
        }
        tDist += stepSize;
    }

    // Exact textureLoad (no filtering) from background
    let res_i = vec2<i32>(res);
    let offset = vec2<i32>(rd.xy * 250.0 * refraction);
    let bgCoord = clamp(vec2<i32>(gid.xy) + offset, vec2<i32>(0), res_i - vec2<i32>(1, 1));
    
    // Chromatic aberration based on refraction
    let chrOff = i32(8.0 * refraction);
    let coordR = clamp(bgCoord + vec2<i32>(chrOff, 0), vec2<i32>(0), res_i - vec2<i32>(1, 1));
    let coordB = clamp(bgCoord - vec2<i32>(chrOff, 0), vec2<i32>(0), res_i - vec2<i32>(1, 1));
    
    let bgR = textureLoad(dataTextureC, coordR, 0).r;
    let bgG = textureLoad(dataTextureC, bgCoord, 0).g;
    let bgB = textureLoad(dataTextureC, coordB, 0).b;
    let bgColor = vec3<f32>(bgR, bgG, bgB);

    var finalColor = bgColor * transmittance + scatteredLight;
    
    // ACES tone map
    finalColor = ACESFilm(finalColor);
    
    // Semantic alpha: 1.0 means fully dense/opaque volume, 0.0 means clear background
    let semanticAlpha = 1.0 - transmittance;

    let outColor = vec4<f32>(finalColor, semanticAlpha);
    
    textureStore(dataTextureA, vec2<i32>(gid.xy), outColor);
    textureStore(writeTexture, vec2<i32>(gid.xy), outColor);
}
