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

    // Params
    let scanSpeed = u.zoom_params.x * 0.5 + 0.1;   // x: Scan Speed
    let slitWidth = u.zoom_params.y * 0.1 + 0.001; // y: Slit Width
    let warpAmt = u.zoom_params.z;                 // z: Time Warp (Wobble)
    let freeze = u.zoom_params.w;                  // w: Freeze / Decay (0 = keep, 1 = fade)

    // Calculate scan position (0 to 1)
    let scanPos = (time * scanSpeed) % 1.0;

    // Wobble the scan line
    let scanLine = scanPos + sin(uv.y * 10.0 + time) * 0.05 * warpAmt;

    // Current live frame
    let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // History frame (previously stored in A, now in C)
    let history = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);

    // Determine if this pixel is under the scan slit
    // We use a small window around the scanPos
    let dist = abs(uv.x - scanLine);

    var outputColor: vec4<f32>;

    if (dist < slitWidth) {
        // Update history with current frame
        outputColor = current;
    } else {
        // Keep old history
        // Optional decay to avoid stuck pixels forever if inputs change
        outputColor = mix(history, current, freeze * 0.01);
    }

    // Write result to display
    textureStore(writeTexture, global_id.xy, outputColor);

    // Write result to history (dataTextureA) for next frame
    textureStore(dataTextureA, global_id.xy, outputColor);

    // Pass-through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
