// ---------------------------------------------------------------
//  Holographic Glitch – futuristic hologram with RGB separation
//  Simulates unstable holographic projection with scanlines,
//  chromatic aberration, and digital artifacts
// ---------------------------------------------------------------
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
// ---------------------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=time, y=frame, z=resX, w=resY
  zoom_config: vec4<f32>,  // x=mouseX, y=mouseY, z=unused, w=unused
  zoom_params: vec4<f32>,  // x=glitchIntensity, y=scanlineSpeed, z=rgbShift, w=flicker
  ripples: array<vec4<f32>, 50>,
};

// ---------------------------------------------------------------
//  Random functions for glitch effects
// ---------------------------------------------------------------
fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn hash13(p: vec3<f32>) -> f32 {
    let p3 = fract(p * 0.1031);
    let p3_dot = dot(vec3<f32>(p3.x, p3.y, p3.z), vec3<f32>(p3.y, p3.z, p3.x) + 33.33);
    return fract((p3.x + p3.y + p3.z) * p3_dot);
}

// ---------------------------------------------------------------
//  Constants
// ---------------------------------------------------------------
const GLITCH_BLOCK_FREQUENCY: f32 = 5.0;  // How often glitch blocks change per second
const GRID_SIZE: f32 = 50.0;  // Size of the wireframe grid overlay

// ---------------------------------------------------------------
//  Main compute shader
// ---------------------------------------------------------------
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(gid.xy) / resolution;
    let time = u.config.x;
    
    // Get depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    
    // Parameters
    let glitchIntensity = u.zoom_params.x;  // Glitch intensity (0-1)
    let scanlineSpeed = u.zoom_params.y;    // Scanline animation speed (0-1)
    let rgbShift = u.zoom_params.z;         // RGB separation amount (0-1)
    let flicker = u.zoom_params.w;          // Flicker intensity (0-1)
    
    // Random glitch blocks that change over time
    let blockTime = floor(time * GLITCH_BLOCK_FREQUENCY);
    let blockY = floor(uv.y * 20.0);
    let glitchBlock = hash(vec2<f32>(blockY, blockTime));
    
    // Apply horizontal displacement glitch
    var glitchedUV = uv;
    if (glitchBlock > (1.0 - glitchIntensity * 0.3)) {
        let displacement = (hash(vec2<f32>(blockY, blockTime + 0.5)) - 0.5) * glitchIntensity * 0.2;
        glitchedUV.x += displacement;
    }
    
    // RGB chromatic aberration - depth-aware
    let aberrationAmount = rgbShift * 0.01 * (1.0 + depth * 0.5);
    let r = textureSampleLevel(readTexture, u_sampler, glitchedUV + vec2<f32>(aberrationAmount, 0.0), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, glitchedUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, glitchedUV - vec2<f32>(aberrationAmount, 0.0), 0.0).b;
    
    var color = vec4<f32>(r, g, b, 1.0);
    
    // Holographic scanlines
    let scanlinePos = fract(uv.y * 200.0 - time * scanlineSpeed * 2.0);
    let scanline = smoothstep(0.3, 0.5, scanlinePos) - smoothstep(0.5, 0.7, scanlinePos);
    color = vec4<f32>(color.rgb + vec3<f32>(0.0, 0.3, 0.5) * scanline * 0.3, color.a);
    
    // Horizontal scan interference
    let interference = sin(uv.y * 100.0 + time * 10.0 * scanlineSpeed) * 0.5 + 0.5;
    color = vec4<f32>(color.rgb * (1.0 - interference * 0.05), color.a);
    
    // Vertical sync glitch
    let vsyncGlitch = step(0.98, hash(vec2<f32>(floor(time * 2.0), 0.0)));
    if (vsyncGlitch > 0.5) {
        let offset = (hash(vec2<f32>(floor(time * 2.0), 1.0)) - 0.5) * glitchIntensity * 0.3;
        glitchedUV.y += offset;
        color = textureSampleLevel(readTexture, u_sampler, glitchedUV, 0.0);
    }
    
    // Digital artifact noise
    let noise = hash13(vec3<f32>(uv * resolution, time * 10.0));
    if (noise > (1.0 - glitchIntensity * 0.1)) {
        color = vec4<f32>(vec3<f32>(noise), color.a);
    }
    
    // Flicker effect
    let flickerValue = 1.0 - flicker * 0.3 * (sin(time * 30.0) * 0.5 + 0.5);
    color = vec4<f32>(color.rgb * flickerValue, color.a);
    
    // Edge hologram effect - brighter edges
    let edgeX = smoothstep(0.0, 0.05, uv.x) * smoothstep(1.0, 0.95, uv.x);
    let edgeY = smoothstep(0.0, 0.05, uv.y) * smoothstep(1.0, 0.95, uv.y);
    let edgeFade = edgeX * edgeY;
    color = vec4<f32>(color.rgb * (0.5 + edgeFade * 0.5), color.a);
    
    // Holographic tint
    color = vec4<f32>(color.rgb + vec3<f32>(0.0, 0.15, 0.25) * (1.0 - depth * 0.5), color.a);
    
    // Grid overlay
    let grid = abs(fract(uv.x * GRID_SIZE) - 0.5) < 0.05 || abs(fract(uv.y * GRID_SIZE) - 0.5) < 0.05;
    if (grid) {
        color = vec4<f32>(color.rgb + vec3<f32>(0.0, 0.2, 0.3) * 0.1, color.a);
    }
    
    // Temporal persistence for trail effect
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    let blended = mix(color, prev, 0.3);
    textureStore(dataTextureA, gid.xy, blended);
    
    // Add subtle scan interference to persistence
    color = vec4<f32>(max(color.rgb, prev.rgb * 0.5), color.a);
    
    // Output
    textureStore(writeTexture, gid.xy, color);
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
