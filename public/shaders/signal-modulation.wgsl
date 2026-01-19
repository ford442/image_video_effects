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
    let mouse = u.zoom_config.yz; // 0..1

    // Parameters
    // x: Base Frequency (0..1 -> 10..500)
    // y: Base Amplitude (0..1 -> 0..0.5)
    // z: Speed (0..1 -> 0..10)
    // w: RGB Split (0..1 -> 0..0.1)

    let base_freq = u.zoom_params.x * 200.0 + 10.0;
    let base_amp = u.zoom_params.y * 0.1;
    let speed = u.zoom_params.z * 10.0;
    let split_amt = u.zoom_params.w * 0.05;

    // Mouse Modulation
    // Mouse X controls Frequency Modulation (FM)
    // Mouse Y controls Amplitude Modulation (AM)

    // Distance from mouse center also affects intensity
    let dist = distance(uv, mouse);
    let proximity = 1.0 - smoothstep(0.0, 0.5, dist); // Higher near mouse

    // FM: Frequency changes based on Y position (standard FM synthesis) or Mouse X
    let fm_mod = sin(uv.y * 10.0 + time) * mouse.x * 50.0;
    let freq = base_freq + fm_mod;

    // AM: Amplitude modulated by another wave or Mouse Y
    let am_mod = (sin(uv.y * 5.0 - time * 2.0) * 0.5 + 0.5);
    let amp = base_amp + (mouse.y * 0.05 * am_mod);

    // Carrier Wave
    // Use x+y for diagonal waves or just y for scanlines
    let phase = uv.y * freq + time * speed;

    // Displacement vector
    // Standard sine wave displacement
    var displacement = sin(phase) * amp;

    // Add "glitch" jumps if amplitude is high
    if (amp > 0.05) {
        displacement = displacement + (fract(sin(uv.y * 100.0) * 1000.0) - 0.5) * amp;
    }

    // RGB Split Logic
    // R is offset by +displacement
    // G is offset by 0 (or slightly different)
    // B is offset by -displacement or phase shifted

    let shift_r = split_amt * (1.0 + mouse.x * 5.0); // Mouse X enhances split
    let shift_b = split_amt * (1.0 + mouse.y * 5.0); // Mouse Y enhances split

    let uv_r = vec2<f32>(uv.x + displacement + shift_r * sin(phase), uv.y);
    let uv_g = vec2<f32>(uv.x + displacement, uv.y);
    let uv_b = vec2<f32>(uv.x + displacement - shift_b * cos(phase), uv.y);

    // Sample texture with clamping/wrapping
    // Using simple clamping 0..1

    let r = textureSampleLevel(readTexture, u_sampler, clamp(uv_r, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, clamp(uv_g, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, clamp(uv_b, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;

    // Add scanlines (darken every other line)
    // let scanline = sin(uv.y * resolution.y * 1.0) * 0.1;
    // let final_color = vec3<f32>(r, g, b) - scanline;

    textureStore(writeTexture, global_id.xy, vec4<f32>(r, g, b, 1.0));

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
