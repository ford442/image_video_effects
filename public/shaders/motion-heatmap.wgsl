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

fn get_heat_color(t: f32, shift: f32) -> vec3<f32> {
    // Manual gradient for "Heat"
    // 0.0: Black/Transparent
    // 0.3: Blue
    // 0.6: Yellow
    // 1.0: Red/White

    // Apply shift by rotating Hue? Or just offset t?
    // Let's just offset t, wrap around.
    // Actually, heat map usually implies intensity. Shifting intensity map is weird.
    // Let's shift Hue of the result.

    var col = vec3<f32>(0.0);
    if (t < 0.3) {
        col = mix(vec3<f32>(0.0, 0.0, 0.2), vec3<f32>(0.0, 0.0, 1.0), t / 0.3);
    } else if (t < 0.6) {
        col = mix(vec3<f32>(0.0, 0.0, 1.0), vec3<f32>(1.0, 1.0, 0.0), (t - 0.3) / 0.3);
    } else {
        col = mix(vec3<f32>(1.0, 1.0, 0.0), vec3<f32>(1.0, 0.0, 0.0), (t - 0.6) / 0.4);
    }

    if (t > 0.9) {
        col = mix(col, vec3<f32>(1.0, 1.0, 1.0), (t - 0.9) / 0.1);
    }

    // Simple hue shift if desired (by rotating RGB channels? Nah, too complex for now).
    // Let's just stick to the heat map.
    return col;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    // Params
    let decay = u.zoom_params.x;          // Heat Decay
    let sensitivity = u.zoom_params.y;    // Motion Sensitivity
    let mouse_heat = u.zoom_params.z;     // Mouse Heat Amount
    let color_shift = u.zoom_params.w;    // Color Shift (Unused currently, keep simplified)

    // Read Current Video
    let currColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let currLuma = dot(currColor.rgb, vec3<f32>(0.299, 0.587, 0.114));

    // Read History (Heat + PrevLuma)
    // R = Heat, A = PrevLuma
    let history = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
    let prevHeat = history.r;
    let prevLuma = history.a;

    // Calculate Motion
    let motion = abs(currLuma - prevLuma);

    // Update Heat
    var newHeat = prevHeat * (1.0 - decay);

    // Add Motion Heat
    newHeat = newHeat + (motion * sensitivity * 0.1);

    // Add Mouse Heat
    let mousePos = u.zoom_config.yz;
    let mouseDistVec = (uv - mousePos) * vec2<f32>(aspect, 1.0);
    let dist = length(mouseDistVec);
    let radius = 0.05;

    if (dist < radius) {
        let falloff = 1.0 - (dist / radius);
        newHeat = newHeat + (mouse_heat * falloff * 0.1);
    }

    // Clamp Heat
    newHeat = clamp(newHeat, 0.0, 2.0);

    // Write State (Heat, 0, 0, CurrLuma)
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(newHeat, 0.0, 0.0, currLuma));

    // Render
    let displayHeat = clamp(newHeat, 0.0, 1.0);
    let heatColor = get_heat_color(displayHeat, color_shift);

    // Composite: Additive
    let finalColor = currColor.rgb + heatColor * displayHeat;

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, 1.0));

    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
