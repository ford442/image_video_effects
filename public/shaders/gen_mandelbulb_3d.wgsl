// ═══════════════════════════════════════════════════════════════════════════════
//  gen_mandelbulb_3d.wgsl - 3D Mandelbulb Fractal with Audio Reactivity & Trails
//  
//  Upgraded: 2026-08-21 (Batch 42)
//  Techniques:
//    - 3D Mandelbulb fractal (power 8)
//    - Audio-reactive power, glow, and color shifting via plasmaBuffer
//    - Temporal accumulation trails via dataTextureC
//    - Distance-based alpha (far = transparent)
//    - Orbit traps for coloring variation
// ═══════════════════════════════════════════════════════════════════════════════

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

const PI: f32 = 3.14159265359;

// Mandelbulb distance estimator
fn mandelbulbDE(pos: vec3<f32>, power: f32, maxIter: i32) -> vec2<f32> {
    var z = pos;
    var dr = 1.0;
    var r = 0.0;
    var iterations = 0;
    
    for (var i: i32 = 0; i < maxIter; i = i + 1) {
        r = length(z);
        if (r > 2.0) {
            iterations = i;
            break;
        }
        
        let theta = acos(clamp(z.z / r, -1.0, 1.0));
        let phi = atan2(z.y, z.x);
        
        dr = pow(r, power - 1.0) * power * dr + 1.0;
        
        let zr = pow(r, power);
        let theta2 = theta * power;
        let phi2 = phi * power;
        
        z = zr * vec3<f32>(
            sin(theta2) * cos(phi2),
            sin(theta2) * sin(phi2),
            cos(theta2)
        ) + pos;
        
        iterations = i;
    }
    
    return vec2<f32>(0.5 * log(r) * r / dr, f32(iterations));
}

// Orbit trap coloring
fn orbitTrapColor(pos: vec3<f32>, power: f32, time: f32, audioTint: vec3<f32>) -> vec3<f32> {
    var z = pos;
    var trap = vec3<f32>(1e10);
    var minR = 1e10;
    
    for (var i: i32 = 0; i < 10; i = i + 1) {
        let r = length(z);
        if (r > 2.0) { break; }
        
        trap = min(trap, abs(z));
        minR = min(minR, r);
        
        let theta = acos(clamp(z.z / r, -1.0, 1.0));
        let phi = atan2(z.y, z.x);
        
        let zr = pow(r, power);
        let theta2 = theta * power;
        let phi2 = phi * power;
        
        z = zr * vec3<f32>(
            sin(theta2) * cos(phi2),
            sin(theta2) * sin(phi2),
            cos(theta2)
        ) + pos;
    }
    
    return vec3<f32>(
        0.5 + 0.5 * cos(trap.x * 3.0 + time + audioTint.x),
        0.5 + 0.5 * cos(trap.y * 3.0 + time * 1.2 + 2.0 + audioTint.y),
        0.5 + 0.5 * cos(trap.z * 3.0 + time * 0.8 + 4.0 + audioTint.z)
    );
}

fn calcNormal(pos: vec3<f32>, power: f32) -> vec3<f32> {
    let eps = 0.001;
    let e = vec2<f32>(eps, 0.0);
    
    return normalize(vec3<f32>(
        mandelbulbDE(pos + e.xyy, power, 10).x - mandelbulbDE(pos - e.xyy, power, 10).x,
        mandelbulbDE(pos + e.yxy, power, 10).x - mandelbulbDE(pos - e.yxy, power, 10).x,
        mandelbulbDE(pos + e.yyx, power, 10).x - mandelbulbDE(pos - e.yyx, power, 10).x
    ));
}

fn softShadow(ro: vec3<f32>, rd: vec3<f32>, mint: f32, maxt: f32, power: f32) -> f32 {
    var res = 1.0;
    var t = mint;
    
    for (var i: i32 = 0; i < 16; i = i + 1) {
        if (t >= maxt) { break; }
        let h = mandelbulbDE(ro + rd * t, power, 8).x;
        res = min(res, 8.0 * h / t);
        t += clamp(h, 0.01, 0.1);
        if (h < 0.001) { break; }
    }
    
    return clamp(res, 0.0, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let coord = vec2<u32>(global_id.xy);
    
    if (f32(coord.x) >= resolution.x || f32(coord.y) >= resolution.y) {
        return;
    }
    
    let uv = (vec2<f32>(global_id.xy) - resolution * 0.5) / resolution.y;
    let uvFull = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    
    // Parameters
    let power = 4.0 + u.zoom_params.x * 4.0 + bass * 2.0; // Audio-reactive power
    let zoom = 0.5 + u.zoom_params.y * 2.0; 
    let fogDensity = u.zoom_params.z; 
    let colorShift = u.zoom_params.w + mids * 0.5;
    
    let theta = time * 0.2 + mouse.x * 3.14;
    let phi = sin(time * 0.1) * 0.5 + (mouse.y - 0.5) * 2.0;
    let camPos = vec3<f32>(
        cos(theta) * cos(phi) * zoom,
        sin(phi) * zoom,
        sin(theta) * cos(phi) * zoom
    );
    
    let targetPos = vec3<f32>(0.0);
    let camForward = normalize(targetPos - camPos);
    let camRight = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), camForward));
    let camUp = cross(camForward, camRight);
    
    let rd = normalize(uv.x * camRight + uv.y * camUp + 1.5 * camForward);
    
    var t = 0.0;
    var hit = false;
    var dist = 0.0;
    var iter = 0.0;
    var glow = 0.0;
    
    for (var i: i32 = 0; i < 80; i = i + 1) {
        let pos = camPos + rd * t;
        let de = mandelbulbDE(pos, power, 15);
        dist = de.x;
        iter = de.y;
        
        glow += exp(-dist * 10.0) * 0.05 * bass;
        
        if (dist < 0.001) {
            hit = true;
            break;
        }
        
        t += dist;
        if (t > 5.0) { break; }
    }
    
    var finalRGB: vec3<f32>;
    var finalAlpha: f32;
    
    let inputColor = textureSampleLevel(readTexture, u_sampler, uvFull, 0.0);
    let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uvFull, 0.0).r;
    let opacity = 0.9;

    if (hit) {
        let pos = camPos + rd * t;
        let normal = calcNormal(pos, power);
        
        let lightDir = normalize(vec3<f32>(0.5, 1.0, 0.3));
        let diffuse = max(dot(normal, lightDir), 0.0);
        let halfDir = normalize(lightDir - rd);
        let specular = pow(max(dot(normal, halfDir), 0.0), 32.0);
        let shadow = softShadow(pos, lightDir, 0.01, 2.0, power);
        
        let trapColor = orbitTrapColor(pos, power, time, vec3<f32>(bass, mids, treble));
        let hitColor = mix(vec3<f32>(0.8, 0.7, 0.9), trapColor, 0.5 + colorShift * 0.5);
        
        let shadedColor = hitColor * diffuse * shadow + vec3<f32>(0.1) + vec3<f32>(1.0) * specular + vec3<f32>(glow * 0.5);
        let hitAlpha = 1.0 - smoothstep(2.0, 5.0, t) * fogDensity;
        
        finalRGB = mix(inputColor.rgb, shadedColor, hitAlpha * opacity);
        finalAlpha = max(inputColor.a, hitAlpha * opacity);
    } else {
        finalRGB = inputColor.rgb + vec3<f32>(glow * 0.2, glow * 0.1, glow * 0.3);
        finalAlpha = inputColor.a;
    }
    
    let fogColor = vec3<f32>(0.1, 0.12, 0.15) * (1.0 + bass * 0.5);
    finalRGB = mix(finalRGB, fogColor, smoothstep(1.0, 4.0, t) * fogDensity);
    
    // Temporal Trails
    let prevColor = textureSampleLevel(dataTextureC, u_sampler, uvFull, 0.0).rgb;
    finalRGB = mix(finalRGB, prevColor, 0.5 * (1.0 - hitAlpha));
    
    finalRGB = finalRGB / (1.0 + finalRGB * 0.5);
    let vignette = 1.0 - length(uvFull - 0.5) * 0.4;
    finalRGB *= vignette;
    
    let finalDepth = select(inputDepth, t / 5.0, hit);
    
    textureStore(writeTexture, coord, vec4<f32>(finalRGB, finalAlpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(finalDepth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(finalRGB, finalAlpha));
}
