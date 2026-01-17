// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// Interactive Pixel Wind
// Param1: Wind Strength
// Param2: Turbulence
// Param3: Trail Length
// Param4: Color Shift

fn random(st: vec2<f32>) -> f32 {
    return fract(sin(dot(st.xy, vec2<f32>(12.9898, 78.233))) * 43758.5453123);
}

fn noise(st: vec2<f32>) -> f32 {
    let i = floor(st);
    let f = fract(st);
    let a = random(i);
    let b = random(i + vec2<f32>(1.0, 0.0));
    let c = random(i + vec2<f32>(0.0, 1.0));
    let d = random(i + vec2<f32>(1.0, 1.0));
    let u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;

    let strength = u.zoom_params.x * 0.1; // Max wind speed
    let turbulence = u.zoom_params.y;
    let trails = u.zoom_params.z;
    let shift = u.zoom_params.w;

    // Calculate wind vector based on mouse position relative to center
    // Center is (0.5, 0.5)
    var windDir = vec2<f32>(0.0);
    if (mousePos.x >= 0.0) {
        windDir = mousePos - vec2<f32>(0.5);
    } else {
        // Default wind if no mouse interaction
        windDir = vec2<f32>(sin(time * 0.5), cos(time * 0.5)) * 0.5;
    }

    // Per-pixel noise for turbulence
    let n = noise(uv * 10.0 + vec2<f32>(time));
    let turbOffset = (vec2<f32>(n) - 0.5) * turbulence * 0.05;

    let offset = windDir * strength + turbOffset;

    // Sample current frame with offset
    var color = textureSampleLevel(readTexture, u_sampler, uv - offset, 0.0);

    // Chromatic aberration (Color Shift) based on wind speed
    let redOffset = offset * (1.0 + shift * 5.0);
    let blueOffset = offset * (1.0 - shift * 5.0);
    let r = textureSampleLevel(readTexture, u_sampler, uv - redOffset, 0.0).r;
    let b = textureSampleLevel(readTexture, u_sampler, uv - blueOffset, 0.0).b;
    color = vec4<f32>(r, color.g, b, color.a);

    // Feedback trail (Wind carries the trails too)
    let historyUV = uv - offset * 0.5; // Trails move slower
    let history = textureSampleLevel(dataTextureC, u_sampler, historyUV, 0.0);

    // Blend
    let finalColor = mix(color, history, trails);

    textureStore(writeTexture, global_id.xy, finalColor);

    // Store history
    textureStore(dataTextureA, global_id.xy, finalColor);

    // Pass depth
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
