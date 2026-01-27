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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let mouse = u.zoom_config.yz;

    // Params
    let intensity = u.zoom_params.x; // Leak Intensity
    let warmth = u.zoom_params.y;    // Warmth (Red/Orange vs Blue/White)
    let size = u.zoom_params.z;      // Blob Size
    let speed = u.zoom_params.w;     // Movement Speed

    var color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    // Generate Light Leaks
    // We create a few "blobs" moving around
    let safeSize = max(0.001, size);

    // Blob 1: Controlled by mouse
    let distMouse = distance(uv, mouse);
    let blob1 = smoothstep(safeSize, 0.0, distMouse); // 1.0 at center

    // Blob 2: Moving autonomously
    let move2 = vec2<f32>(sin(time * speed * 0.5), cos(time * speed * 0.3)) * 0.5 + 0.5;
    let dist2 = distance(uv, move2);
    let blob2 = smoothstep(safeSize * 1.5, 0.0, dist2);

    // Blob 3: Another one
    let move3 = vec2<f32>(cos(time * speed * 0.7), sin(time * speed * 0.4)) * 0.5 + 0.5;
    let dist3 = distance(uv, move3);
    let blob3 = smoothstep(safeSize * 1.2, 0.0, dist3);

    // Combine blobs
    let totalLeak = (blob1 + blob2 * 0.7 + blob3 * 0.5) * intensity;

    // Determine Color
    // Warm: Red/Orange. Cold: Blue/Cyan.
    let warmColor = vec3<f32>(1.0, 0.5, 0.2);
    let coldColor = vec3<f32>(0.2, 0.5, 1.0);

    // Mix based on warmth param
    let leakColor = mix(coldColor, warmColor, warmth);

    // Add extra white hot core
    let core = smoothstep(0.8, 1.0, totalLeak);
    let finalLeakColor = mix(leakColor, vec3<f32>(1.0), core);

    // Apply Screen Blending
    color = 1.0 - (1.0 - color) * (1.0 - finalLeakColor * totalLeak);

    textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));
}
