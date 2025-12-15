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
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2 (w=isMouseDown)
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn thermal_gradient(t: f32, shift: f32) -> vec3<f32> {
    // Offset t by shift
    let t_mod = fract(t + shift);
    var col = vec3<f32>(0.0);

    // Gradient: Black -> Blue -> Purple -> Red -> Orange -> Yellow -> White
    if (t_mod < 0.2) {
        // Black to Blue
        col = mix(vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), t_mod * 5.0);
    } else if (t_mod < 0.4) {
        // Blue to Purple/Magenta
        col = mix(vec3(0.0, 0.0, 1.0), vec3(1.0, 0.0, 1.0), (t_mod - 0.2) * 5.0);
    } else if (t_mod < 0.6) {
        // Purple to Red
        col = mix(vec3(1.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0), (t_mod - 0.4) * 5.0);
    } else if (t_mod < 0.8) {
        // Red to Yellow
        col = mix(vec3(1.0, 0.0, 0.0), vec3(1.0, 1.0, 0.0), (t_mod - 0.6) * 5.0);
    } else {
        // Yellow to White
        col = mix(vec3(1.0, 1.0, 0.0), vec3(1.0, 1.0, 1.0), (t_mod - 0.8) * 5.0);
    }
    return col;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;

    // Parameters
    let heatIntensity = u.zoom_params.x * 2.0 - 1.0; // -1.0 to 1.0
    let heatRadius = u.zoom_params.y; // 0.0 to 1.0
    let contrast = mix(0.2, 5.0, u.zoom_params.z); // 0.2 to 5.0
    let shift = u.zoom_params.w; // 0.0 to 1.0

    let base = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    var lum = dot(base.rgb, vec3(0.299, 0.587, 0.114));

    // Contrast
    lum = pow(lum, contrast);

    // Mouse Heat
    let mousePos = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;
    // Aspect correct distance
    let dist = distance(uv * vec2(aspect, 1.0), mousePos * vec2(aspect, 1.0));

    let r = heatRadius * 0.5;
    let heat = smoothstep(r, 0.0, dist) * heatIntensity;

    lum = clamp(lum + heat, 0.0, 1.0);

    let finalColor = thermal_gradient(lum, shift);
    textureStore(writeTexture, global_id.xy, vec4(finalColor, 1.0));

    // Pass-through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
