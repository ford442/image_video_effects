// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // Use for persistence/trail history
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>; // Or generic object data
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4 (Use these for ANY float sliders)
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    // Params
    let waveSpeed = u.zoom_params.x; // 0.1 to 1.0
    let mouseForce = u.zoom_params.y; // 0.0 to 1.0
    let damping = u.zoom_params.z; // 0.9 to 0.99
    let refractionAmt = u.zoom_params.w; // 0.0 to 1.0

    // Read previous state from history (dataTextureC)
    // Red = height, Green = velocity
    let state = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    var h = state.r;
    var v = state.g;

    // Sample neighbors for Laplacian
    let texel = 1.0 / resolution;
    let n = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(0.0, -texel.y), 0.0).r;
    let s = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(0.0, texel.y), 0.0).r;
    let e = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(texel.x, 0.0), 0.0).r;
    let w = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(-texel.x, 0.0), 0.0).r;

    // Calculate wave propagation
    let laplacian = (n + s + e + w) / 4.0 - h;

    // Input image luminance modulates the wave speed
    // Bright areas = fast waves (water), Dark areas = slow waves (molasses)
    let imgColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let luma = dot(imgColor, vec3<f32>(0.299, 0.587, 0.114));

    // Map luma to speed multiplier: 0.2 to 1.2
    let localSpeed = waveSpeed * (0.2 + 1.0 * luma);

    // Integrate
    v = v + laplacian * localSpeed;
    v = v * damping; // damping

    // Mouse Interaction: Click or Move adds force
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let dist = distance(uv * vec2<f32>(aspect, 1.0), mouse * vec2<f32>(aspect, 1.0));

    // Continuous disturbance if mouse is down
    if (mouseDown > 0.5 && dist < 0.05) {
        // Add a "hump" or depression
        v = v + (1.0 - dist / 0.05) * mouseForce * 0.5;
    }

    // Update height
    h = h + v;

    // Clamp height to prevent explosion
    h = clamp(h, -10.0, 10.0);

    // Store new state
    textureStore(dataTextureA, global_id.xy, vec4<f32>(h, v, 0.0, 1.0));

    // Render: Refract input texture based on height gradient
    let gradX = (e - w) * 0.5;
    let gradY = (s - n) * 0.5;

    let normal = vec2<f32>(gradX, gradY);
    let finalUV = uv - normal * refractionAmt * 0.5;

    let finalColor = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0);

    textureStore(writeTexture, global_id.xy, finalColor);

    // Pass-through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
