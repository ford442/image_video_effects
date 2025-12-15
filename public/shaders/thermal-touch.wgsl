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

fn get_thermal_color(val: f32) -> vec3<f32> {
    // Simple heatmap gradient: Blue -> Cyan -> Green -> Yellow -> Red -> White
    let v = clamp(val, 0.0, 1.0);
    if (v < 0.25) { return mix(vec3(0.0, 0.0, 0.5), vec3(0.0, 1.0, 1.0), v * 4.0); }
    if (v < 0.5) { return mix(vec3(0.0, 1.0, 1.0), vec3(0.0, 1.0, 0.0), (v - 0.25) * 4.0); }
    if (v < 0.75) { return mix(vec3(0.0, 1.0, 0.0), vec3(1.0, 1.0, 0.0), (v - 0.5) * 4.0); }
    return mix(vec3(1.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), (v - 0.75) * 4.0);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;

    // Params
    let heatIntensity = mix(0.1, 2.0, u.zoom_params.x); // Strength
    let radius = mix(0.05, 0.5, u.zoom_params.y);       // Radius
    let ambientTemp = u.zoom_params.z;                  // Ambient
    let colorMode = u.zoom_params.w;                    // 0 = Normal, 1 = Inverted/Other

    // Mouse Info
    let mousePos = u.zoom_config.yz;

    // Correct aspect for distance
    let aspect = resolution.x / resolution.y;
    let distVec = (uv - mousePos) * vec2(aspect, 1.0);
    let dist = length(distVec);

    // Calculate Mouse Heat influence
    let mouseHeat = (1.0 - smoothstep(0.0, radius, dist)) * heatIntensity;

    // Sample texture
    let texColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let luminance = dot(texColor, vec3(0.299, 0.587, 0.114));

    // Final Heat Value
    // Base heat from image brightness + mouse heat
    var heat = luminance + mouseHeat;
    if (ambientTemp > 0.0) {
        heat = mix(heat, ambientTemp, 0.3); // Blend towards ambient
    }

    // Map to color
    var finalColor = get_thermal_color(heat);

    // Optional: Mix original texture back in based on colorMode
    if (colorMode > 0.5) {
         finalColor = mix(finalColor, texColor, 0.5);
    }

    textureStore(writeTexture, global_id.xy, vec4(finalColor, 1.0));

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4(depth, 0.0, 0.0, 0.0));
}
