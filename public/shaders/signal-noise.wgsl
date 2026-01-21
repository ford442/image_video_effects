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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn hash(p: f32) -> f32 {
    return fract(sin(p) * 43758.5453);
}

fn noise(p: f32) -> f32 {
    let i = floor(p);
    let f = fract(p);
    return mix(hash(i), hash(i + 1.0), smoothstep(0.0, 1.0, f));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let t = u.zoom_config.x;
    let mouse = u.zoom_config.yz;

    // Y-distance controls "tuning" / frequency
    let tuning = mix(10.0, 100.0, mouse.y);

    // X-distance controls intensity
    let intensity = mix(0.0, 0.2, mouse.x);

    // Create scanline bands
    let scanline = floor(uv.y * tuning);
    let shift = noise(scanline + t * 5.0) * 2.0 - 1.0; // -1 to 1

    // Only apply shift if above a random threshold (intermittent glitch)
    let trigger = step(0.8, hash(scanline * 0.1 + t));
    let x_offset = shift * intensity * trigger;

    // Add RGB split
    let r_offset = x_offset * 1.5;
    let b_offset = x_offset * 0.5;

    let r = textureSampleLevel(readTexture, u_sampler, vec2<f32>(uv.x + r_offset, uv.y), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, vec2<f32>(uv.x + x_offset, uv.y), 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, vec2<f32>(uv.x + b_offset, uv.y), 0.0).b;

    // Add horizontal noise lines (static)
    let static_noise = hash(uv.y * 500.0 + t) * hash(uv.x * 500.0);
    let static_intensity = intensity * 0.5 * trigger;

    let color = vec3<f32>(r, g, b) + vec3<f32>(static_noise * static_intensity);

    textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));
}
