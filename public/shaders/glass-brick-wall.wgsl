// ================================================================
//  Glass Brick Wall
//  Category: distortion
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba,
//            caustic-refraction, depth-layers, chromatic-dispersion, fbm-texture
//  Complexity: Very High
//  Chunks From: glass-brick-wall
//  Created: 2026-05-31
//  Upgraded: 2026-06-28
//  By: The Complexity Architect
// ================================================================

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
  zoom_params: vec4<f32>,  // x=BrickSize, y=Distortion, z=MortarSize, w=GlassDensity
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn aces_approx(v: vec3<f32>) -> vec3<f32> {
    var color = v * 0.6;
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((color * (a * color + b)) / (color * (c * color + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash12(p: vec2<f32>) -> f32 {
  let h = sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453;
  return fract(h);
}

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash12(i + vec2<f32>(0.0, 0.0)), hash12(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y
  );
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var total = 0.0;
  var amplitude = 0.5;
  var frequency = 1.0;
  for (var i = 0; i < octaves; i = i + 1) {
    total = total + amplitude * noise2(p * frequency);
    amplitude = amplitude * 0.5;
    frequency = frequency * 2.1;
  }
  return total;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = u.config.zw;
    if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) {
        return;
    }

    let time = u.config.x;
    let dt = u.config.y;
    let is_click = u.zoom_config.x;
    let mouse = u.zoom_config.yz;
    let aspect = dims.x / dims.y;
    let uv = vec2<f32>(gid.xy) / dims;

    // Single-writer spring state in extraBuffer[133..138]
    if (gid.x == 0u && gid.y == 0u) {
        let px = extraBuffer[134];
        let py = extraBuffer[135];
        let vx = extraBuffer[136];
        let vy = extraBuffer[137];
        
        let tx = mouse.x;
        let ty = mouse.y;
        
        let k = 8.0;
        let damp = 0.8;
        
        var ax = (tx - px) * k - vx * damp;
        var ay = (ty - py) * k - vy * damp;
        
        var nvx = vx + ax * dt;
        var nvy = vy + ay * dt;
        let speed = length(vec2<f32>(nvx, nvy));
        if (speed > 5.0) {
            nvx = (nvx / speed) * 5.0;
            nvy = (nvy / speed) * 5.0;
        }
        
        var npx = px + nvx * dt;
        var npy = py + nvy * dt;
        
        if (is_click > 0.5 && extraBuffer[133] < 0.5) {
            extraBuffer[138] = 0.0;
        } else {
            extraBuffer[138] += dt;
        }
        
        extraBuffer[133] = is_click;
        extraBuffer[134] = npx;
        extraBuffer[135] = npy;
        extraBuffer[136] = nvx;
        extraBuffer[137] = nvy;
    }
    workgroupBarrier();

    let spring_pos = vec2<f32>(extraBuffer[134], extraBuffer[135]);
    let click_time = extraBuffer[138];

    // Audio reactivity
    let bass = plasmaBuffer[0].x;
    let mid = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let brickSize = mix(10.0, 54.0, u.zoom_params.x);
    let distortion = mix(0.0, 0.12, u.zoom_params.y);
    let mortarSize = mix(0.01, 0.12, u.zoom_params.z);
    let glassDensity = mix(0.6, 2.6, u.zoom_params.w);

    let gridUV = uv * vec2<f32>(brickSize * aspect, brickSize);
    let cellId = floor(gridUV);
    let cell = fract(gridUV) - 0.5;
    let r2 = dot(cell, cell) * 4.0;

    // FBM-perturbed normal for organic glass surface
    let normalNoise = fbm(cell * 4.0 + cellId * 0.5 + time * 0.05, 5) * 0.15;
    let normalXY = cell * -2.0 + vec2<f32>(normalNoise, normalNoise * 0.7);
    let normalZ = sqrt(max(0.0, 1.0 - dot(normalXY, normalXY)));
    let normal = normalize(vec3<f32>(normalXY, normalZ));
    let mortarMask = smoothstep(0.48 - mortarSize, 0.5, max(abs(cell.x), abs(cell.y)));

    // Held pointer / Continuous geometry
    let p_dist = distance(uv * vec2<f32>(aspect, 1.0), spring_pos * vec2<f32>(aspect, 1.0));
    let ptr_influence = smoothstep(0.3, 0.0, p_dist) * (1.0 + bass * 0.5);

    // Capped click fronts
    let wave_radius = click_time * 0.5;
    let click_dist = abs(p_dist - wave_radius);
    let click_wave = smoothstep(0.1, 0.0, click_dist) * smoothstep(1.5, 0.0, click_time) * min(1.0, click_time * 5.0);

    let refractOffset = normal.xy * distortion * (1.0 - mortarMask) * (1.0 + bass * 0.35 + ptr_influence * 0.2 + click_wave * 0.5);
    let frontUV = clamp(uv + refractOffset, vec2<f32>(0.0), vec2<f32>(1.0));

    let bgData = textureLoad(dataTextureC, vec2<i32>(gid.xy), 0);
    
    // Chromatic dispersion pseudo
    let cr = textureSampleLevel(readTexture, u_sampler, frontUV + vec2<f32>(0.005) * treble, 0.0).r;
    let cg = textureSampleLevel(readTexture, u_sampler, frontUV, 0.0).g;
    let cb = textureSampleLevel(readTexture, u_sampler, frontUV - vec2<f32>(0.005) * treble, 0.0).b;
    let base_a = textureSampleLevel(readTexture, u_sampler, frontUV, 0.0).a;
    
    var color = vec3<f32>(cr, cg, cb) + bgData.xyz * 0.01;
    
    // Capped Glass shading
    var finalAlpha = base_a;
    if (mortarMask < 0.5) {
        let lightDir = normalize(vec3<f32>(0.0, 0.0, 1.0)); // simplified
        let spec = pow(max(dot(normal, lightDir), 0.0), 32.0) * (0.5 + mid);
        let glassColor = vec3<f32>(0.8, 0.9, 1.0) * (1.0 - glassDensity * 0.2);
        color = color * glassColor + spec;
        finalAlpha = mix(0.8, 0.2, (1.0 - mortarMask)); 
    } else {
        color *= 0.3; // mortar is dark
        finalAlpha = 0.95;
    }
    
    color += ptr_influence * vec3<f32>(0.2, 0.4, 0.8) * mid;
    color += click_wave * vec3<f32>(1.0, 0.8, 0.4);

    color = aces_approx(color);
    let finalOutput = vec4<f32>(color, finalAlpha);

    textureStore(dataTextureA, vec2<i32>(gid.xy), finalOutput);
    textureStore(writeTexture, vec2<i32>(gid.xy), finalOutput);
    
    let baseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, frontUV, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(baseDepth, 0.0, 0.0, 0.0));
}
