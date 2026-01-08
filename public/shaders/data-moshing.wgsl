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
    let smearStrength = u.zoom_params.x; // Force of the mouse drag
    let radius = u.zoom_params.y; // Mouse radius
    let decay = u.zoom_params.z; // How fast offsets heal (0.0 = fast heal, 1.0 = permanent)
    let quantize = u.zoom_params.w; // Color bit crushing

    // Read previous UV offset from history
    let prevData = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    var offset = prevData.xy;

    // Mouse Interaction
    let mouse = u.zoom_config.yz;
    let dist = distance(uv * vec2<f32>(aspect, 1.0), mouse * vec2<f32>(aspect, 1.0));

    // If inside mouse radius, push the offset
    if (dist < radius) {
        // Calculate a push direction
        // Since we don't have mouse delta, we push away from center of mouse (repel)
        // Or swirl?
        // Let's use a flow based on time to create "turbulence" near mouse

        let time = u.config.x;
        let angle = atan2(uv.y - mouse.y, uv.x - mouse.x);
        // Swirl
        let swirl = vec2<f32>(cos(angle + time), sin(angle + time));

        // Push amount
        let force = (1.0 - dist/radius) * smearStrength * 0.02;

        offset = offset + swirl * force;
    }

    // Apply decay (healing)
    // We want decay to be inverse: 1.0 = no decay (persistence), 0.0 = instant heal
    offset = offset * (0.9 + 0.09 * decay);

    // Limit offset to prevent total garbage
    offset = clamp(offset, vec2<f32>(-0.5), vec2<f32>(0.5));

    // Sample texture with offset
    let distortedUV = uv - offset; // Subtract offset to look "back"
    let color = textureSampleLevel(readTexture, u_sampler, distortedUV, 0.0);

    // Color Quantization (Glitch effect)
    var finalColor = color;
    if (quantize > 0.0) {
        let q = 20.0 * (1.0 - quantize) + 1.0; // 1 to 21 levels
        finalColor = floor(color * q) / q;
    }

    textureStore(writeTexture, global_id.xy, finalColor);
    textureStore(dataTextureA, global_id.xy, vec4<f32>(offset, 0.0, 0.0));

    // Depth passthrough
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
