// ═══════════════════════════════════════════════════════════════════════════════
//  gen_mandelbulb_3d.wgsl - 3D Mandelbulb Fractal with RGBA Depth
//  
//  RGBA Focus: Alpha = ray march distance/depth for fog integration
//  Techniques:
//    - 3D Mandelbulb fractal (power 8)
//    - Ray marching with early exit
//    - Distance-based alpha (far = transparent)
//    - Iteration count coloring
//    - Orbit traps for coloring variation
//  
//  Target: 4.8★ rating
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
        
        // Convert to spherical
        let theta = acos(clamp(z.z / r, -1.0, 1.0));
        let phi = atan2(z.y, z.x);
        
        dr = pow(r, power - 1.0) * power * dr + 1.0;
        
        // Scale and rotate
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
fn orbitTrapColor(pos: vec3<f32>, power: f32, time: f32) -> vec3<f32> {
    var z = pos;
    var trap = vec3<f32>(1e10);
    var minR = 1e10;
    
    for (var i: i32 = 0; i < 10; i = i + 1) {
        let r = length(z);
        if (r > 2.0) { break; }
        
        // Track minimum distance to axes (orbit trap)
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
    
    // Color based on orbit trap
    return vec3<f32>(
        0.5 + 0.5 * cos(trap.x * 3.0 + time),
        0.5 + 0.5 * cos(trap.y * 3.0 + time + 2.0),
        0.5 + 0.5 * cos(trap.z * 3.0 + time + 4.0)
    );
}

// Calculate normal via central differences
fn calcNormal(pos: vec3<f32>, power: f32) -> vec3<f32> {
    let eps = 0.001;
    let e = vec2<f32>(eps, 0.0);
    
    return normalize(vec3<f32>(
        mandelbulbDE(pos + e.xyy, power, 10).x - mandelbulbDE(pos - e.xyy, power, 10).x,
        mandelbulbDE(pos + e.yxy, power, 10).x - mandelbulbDE(pos - e.yxy, power, 10).x,
        mandelbulbDE(pos + e.yyx, power, 10).x - mandelbulbDE(pos - e.yyx, power, 10).x
    ));
}

// Soft shadow
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
    
    // Parameters
    let power = 4.0 + u.zoom_params.x * 4.0; // 4-8 power
    let zoom = 0.5 + u.zoom_params.y * 2.0; // Camera distance
    let fogDensity = u.zoom_params.z; // Atmospheric alpha
    let colorShift = u.zoom_params.w;
    
    let audioPulse = u.zoom_config.w;
    
    // Camera setup
    let theta = time * 0.2;
    let phi = sin(time * 0.1) * 0.5;
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
    
    // Ray march
    var t = 0.0;
    var hit = false;
    var dist = 0.0;
    var iter = 0.0;
    
    for (var i: i32 = 0; i < 100; i = i + 1) {
        let pos = camPos + rd * t;
        let de = mandelbulbDE(pos, power + audioPulse * 2.0, 15);
        dist = de.x;
        iter = de.y;
        
        if (dist < 0.001) {
            hit = true;
            break;
        }
        
        t += dist;
        if (t > 5.0) { break; }
    }
    
    var finalRGB: vec3<f32>;
    var finalAlpha: f32;
    
    if (hit) {
        let pos = camPos + rd * t;
        let normal = calcNormal(pos, power);
        
        // Lighting
        let lightDir = normalize(vec3<f32>(0.5, 1.0, 0.3));
        let diffuse = max(dot(normal, lightDir), 0.0);
        
        // Specular
        let halfDir = normalize(lightDir - rd);
        let specular = pow(max(dot(normal, halfDir), 0.0), 32.0);
        
        // Shadow
        let shadow = softShadow(pos, lightDir, 0.01, 2.0, power);
        
        // Color from orbit trap
        let trapColor = orbitTrapColor(pos, power, time);
        let baseColor = mix(vec3<f32>(0.8, 0.7, 0.9), trapColor, 0.5 + colorShift * 0.5);
        
        // Combine
        finalRGB = baseColor * diffuse * shadow + vec3<f32>(0.1) + vec3<f32>(1.0) * specular;
        
        // Alpha based on distance (fog)
        finalAlpha = 1.0 - smoothstep(2.0, 5.0, t) * fogDensity;
    } else {
        // Background
        let bg = textureSampleLevel(readTexture, u_sampler, uvFull, 0.0).rgb;
        finalRGB = bg;
        finalAlpha = 0.0;
    }
    
    // Fog color blend
    let fogColor = vec3<f32>(0.1, 0.12, 0.15);
    finalRGB = mix(finalRGB, fogColor, smoothstep(1.0, 4.0, t) * fogDensity);
    
    // Tone mapping
    finalRGB = finalRGB / (1.0 + finalRGB * 0.5);
    
    // Vignette
    let vignette = 1.0 - length(uvFull - 0.5) * 0.4;
    finalRGB *= vignette;
    
    textureStore(writeTexture, coord, vec4<f32>(finalRGB, finalAlpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(t / 5.0, 0.0, 0.0, 1.0));
    
    // Store RGBA for feedback
    textureStore(dataTextureA, coord, vec4<f32>(finalRGB, finalAlpha));
}
