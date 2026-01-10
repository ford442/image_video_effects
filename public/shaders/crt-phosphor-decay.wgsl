// ═══════════════════════════════════════════════════════════════
//  CRT Phosphor Decay
//  Simulates the persistence of vision of a CRT monitor.
//  Bright pixels leave a ghost trail that fades slowly.
// ═══════════════════════════════════════════════════════════════

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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=DecayRate, y=BrightnessBoost, z=ScanlineOpacity, w=NoiseLevel
  ripples: array<vec4<f32>, 50>,
};

// Simple pseudo-random hash
fn hash12(p: vec2<f32>) -> f32 {
    let p3 = fract(vec3<f32>(p.xyx) * .1031);
    let p3_mod = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3_mod.x + p3_mod.y) * p3_mod.z);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;

    // Params
    let decayRate = mix(0.5, 0.99, u.zoom_params.x); // High = long trails
    let boost = 1.0 + u.zoom_params.y * 2.0;
    let scanlineStr = u.zoom_params.z;
    let noiseLevel = u.zoom_params.w;

    // Read current frame
    let currColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Read history (previous frame's output stored in C)
    let prevColor = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);

    // Apply decay to history
    // We want the max of (Current, Previous * decay) to simulate phosphor holding charge
    // This creates the "smear" or "ghosting"
    let historyDecayed = prevColor * decayRate;

    // Brightness boost for the "fresh" phosphor hit
    let freshColor = currColor * boost;

    // Combine: Phosphors light up instantly, fade slowly
    let combinedColor = max(freshColor, historyDecayed);

    // Mouse Interaction: Touch "activates" phosphors (static/white noise)
    let mouse = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;
    let dist = distance(vec2<f32>(uv.x * aspect, uv.y), vec2<f32>(mouse.x * aspect, mouse.y));

    var staticNoise = 0.0;
    if (dist < 0.15 && noiseLevel > 0.0) {
        let h = hash12(uv * u.config.x); // Animated noise
        let falloff = smoothstep(0.15, 0.0, dist);
        staticNoise = h * falloff * noiseLevel;
    }

    var finalColor = combinedColor + vec4<f32>(staticNoise);

    // Scanlines
    // Simple sine wave based on UV.y and resolution
    let scanline = sin(uv.y * resolution.y * 0.5) * 0.5 + 0.5;
    // Darken rows
    let scanlineFactor = mix(1.0, scanline, scanlineStr);

    finalColor = vec4<f32>(finalColor.rgb * scanlineFactor, 1.0);

    // Store logic
    // We need to store the *undecayed* (or slightly decayed) state for next frame
    // Ideally we store 'combinedColor' BEFORE scanlines, so scanlines don't get "burned in" recursively
    // if we don't want them to.
    // However, if we store combinedColor, it accumulates max brightness.

    // We store the raw phosphor state in A (which goes to C next frame)
    textureStore(dataTextureA, vec2<i32>(global_id.xy), combinedColor);

    // Write to display (with scanlines)
    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
}
