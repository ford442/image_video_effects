// ═══════════════════════════════════════════════════════════════════
//  Motion Heatmap
//  Category: image
//  Features: motion-detection, heatmap, mouse-driven, temporal-feedback, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-06-28
//  By: Agent 1a - Alpha Channel Specialist
// ═══════════════════════════════════════════════════════════════════

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

    // Rotate the established heat palette without changing intensity.
    let rotated = vec3<f32>(col.g, col.b, col.r);
    return mix(col, rotated, clamp(shift, 0.0, 1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let coord = vec2<i32>(global_id.xy);
    let maxCoord = vec2<i32>(i32(resolution.x) - 1, i32(resolution.y) - 1);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let time = u.config.x;
    let audio = plasmaBuffer[0].xyz;

    // Params
    let decay = clamp(u.zoom_params.x, 0.001, 0.3);
    let sensitivity = clamp(u.zoom_params.y, 0.0, 10.0);
    let mouse_heat = clamp(u.zoom_params.z, 0.0, 2.0);
    let color_shift = clamp(u.zoom_params.w, 0.0, 1.0);

    // Read Current Video
    let currColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let currLuma = dot(currColor.rgb, vec3<f32>(0.299, 0.587, 0.114));

    // Read History (Heat + PrevLuma)
    // R = Heat, A = PrevLuma
    let flow = vec2<f32>(
        sin(uv.y * 15.0 + time * 3.2),
        -1.0 - audio.x * 1.5
    );
    let flowPixels = vec2<i32>(round(flow * vec2<f32>(2.0, 1.5)));
    let advectedCoord = clamp(coord - flowPixels, vec2<i32>(0), maxCoord);
    let history = textureLoad(dataTextureC, advectedCoord, 0);
    let localHistory = textureLoad(dataTextureC, coord, 0);
    let prevHeat = history.r;
    let prevLuma = localHistory.a;

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
        let heldBoost = mix(0.35, 1.0, step(0.5, u.zoom_config.w));
        newHeat = newHeat + (mouse_heat * falloff * 0.1 * heldBoost);
    }

    // Fast motion: bright heat packets race along the advected flow field.
    let runnerPhase = dot(uv * vec2<f32>(aspect, 1.0), normalize(flow + vec2<f32>(0.001))) * 55.0 - time * 14.0;
    let heatRunner = pow(max(0.0, sin(runnerPhase)), 14.0) * (motion * sensitivity + audio.y * 0.08);
    newHeat += heatRunner;

    // Clicks launch bounded thermal fronts without persistent buffer state.
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 2.0) {
            let delta = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
            let ring = smoothstep(0.025, 0.0, abs(length(delta) - age * 0.42));
            newHeat += ring * exp(-age * 1.4) * (0.65 + audio.x * 0.35);
        }
    }

    // Clamp Heat
    newHeat = clamp(newHeat, 0.0, 2.0);

    // Write State (Heat, 0, 0, CurrLuma)
    textureStore(dataTextureA, coord, vec4<f32>(newHeat, 0.0, 0.0, currLuma));

    // Render
    let displayHeat = clamp(newHeat, 0.0, 1.0);
    let heatColor = get_heat_color(displayHeat, color_shift);

    // Composite: Additive, preserving input alpha
    let finalColor = clamp(currColor.rgb + heatColor * displayHeat, vec3<f32>(0.0), vec3<f32>(4.0));

    textureStore(writeTexture, coord, vec4<f32>(finalColor, currColor.a));

    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
