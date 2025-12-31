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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let mousePos = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;

    // Params
    let intensity = u.zoom_params.x * 0.05; // Max shift amount
    let radius = u.zoom_params.y;
    let falloff = u.zoom_params.z;
    let angle_offset = (u.zoom_params.w - 0.5) * 6.28; // Rotate the aberration direction

    var dVec = uv - mousePos;
    dVec.x *= aspect;
    let dist = length(dVec);

    // Calculate effect strength based on distance
    // mix(0, 1, dist) ? No, usually 0 at center, 1 at edge, or vice versa.
    // Let's say Intensity increases with distance from mouse (mouse is clear center).
    // Or mouse emits the wave?
    // Let's do: Mouse is center of calmness (0 shift), edges are shifted.
    // Unless "radius" defines the active area.
    // Let's do: Effect is strongest at radius, falls off.
    // Or simpler: Effect scales with distance from mouse.

    let effect = smoothstep(radius, radius + falloff + 0.001, dist);

    // Direction of shift
    let dir = normalize(dVec + vec2<f32>(0.001, 0.001)); // prevent NaN

    // Rotate direction if needed
    let s = sin(angle_offset);
    let c = cos(angle_offset);
    let rDir = vec2(dir.x * c - dir.y * s, dir.x * s + dir.y * c);

    let shift = rDir * intensity * effect * dist; // Scale by dist too for radial explosion feel

    let r = textureSampleLevel(readTexture, u_sampler, uv - shift, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uv + shift, 0.0).b;

    textureStore(writeTexture, global_id.xy, vec4(r, g, b, 1.0));

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4(depth, 0.0, 0.0, 0.0));
}
