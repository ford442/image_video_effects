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
    let mouse = u.zoom_config.yz;
    let time = u.config.x;

    // Params
    let slices = u.zoom_params.x * 50.0 + 1.0; // Number of slices
    let strength = u.zoom_params.y;            // Offset strength
    let phase = u.zoom_params.z * 10.0;        // Phase shift/speed
    let smoothVal = u.zoom_params.w;           // Smoothness

    // Slinky Logic
    // Based on UV.y, we shift UV.x
    // Shift depends on distance from mouse X? Or just sinusoidal?

    // Create bands
    var yFactor = uv.y * slices;
    if (smoothVal < 0.5) {
        yFactor = floor(yFactor); // Hard edges
    }

    // Calculate Offset
    // We want the whole image to sway, but controlled by mouse X
    // Center the sway around mouse.x

    // Basic sine wave
    let wave = sin(yFactor + time * phase);

    // Interaction: Mouse X pulls the center
    // Mouse Y could control amplitude locally?

    let pull = (mouse.x - 0.5) * 2.0; // -1 to 1

    // Offset X
    // Combine wave and mouse pull
    let offsetX = wave * strength * 0.1 + pull * strength * 0.5 * sin(uv.y * 3.14);

    let finalUV = vec2<f32>(uv.x + offsetX, uv.y);

    // Edge handling (mirror or clamp)
    // TextureSample handles clamp usually, but let's mirror manually if needed?
    // Let's just sample.

    let color = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0);

    textureStore(writeTexture, global_id.xy, color);
}
