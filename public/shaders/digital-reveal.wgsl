// ═══════════════════════════════════════════════════════════════════
//  Digital Reveal
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, temporal-digital-rain, depth-reveal, chromatic-drops, upgraded-rgba
//  Complexity: High
//  Chunks From: digital-reveal, bass_env, hash22
//  Created: 2024-01-01
//  Upgraded: 2026-05-31
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx+p3.yz)*p3.zy);
}

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.5 + mids * 0.2;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthReveal = mix(0.3, 1.0, depth);

    let density = u.zoom_params.x * bass_env(bass, mids);
    let revealSize = u.zoom_params.y;
    let trailFade = u.zoom_params.z;
    let rainSpeed = u.zoom_params.w * (1.0 + treble * 0.5);

    let prevVal = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).r;

    let mouse = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;
    let uvCorrected = vec2<f32>(uv.x * aspect, uv.y);
    let mouseCorrected = vec2<f32>(mouse.x * aspect, mouse.y);
    let dist = distance(uvCorrected, mouseCorrected);

    let brushRadius = revealSize * 0.3 + 0.05;
    let brush = smoothstep(brushRadius, brushRadius * 0.5, dist);

    let fadeFactor = 0.8 + trailFade * 0.19;
    let newVal = max(prevVal * fadeFactor, brush) * depthReveal;

    textureStore(dataTextureA, global_id.xy, vec4<f32>(newVal, 0.0, 0.0, 1.0));

    let gridSize = vec2<f32>(20.0, 20.0 * aspect) * (1.0 + density * 2.0);
    let cellUV = fract(uv * gridSize);
    let cellID = floor(uv * gridSize);

    let colSpeed = hash22(vec2<f32>(cellID.x, 0.0)).y * (rainSpeed * 5.0 + 1.0);
    let verticalPos = cellID.y + time * colSpeed;
    let charID = floor(verticalPos);
    let dropVal = fract(verticalPos);
    let charBright = smoothstep(0.0, 0.2, dropVal) * smoothstep(1.0, 0.8, dropVal);
    let flicker = step(0.1, hash22(vec2<f32>(cellID.x, charID)).x);

    // Chromatic drops: bass shifts green, treble shifts cyan/white highlights
    var rainColor = vec3<f32>(0.0, 1.0, 0.2) * charBright * flicker;
    rainColor.g = rainColor.g + bass * 0.3 * charBright;
    if (hash22(vec2<f32>(cellID.x, charID)).y > 0.98 - density * 0.1) {
        rainColor = vec3<f32>(0.8 + treble * 0.2, 1.0, 0.8 + treble * 0.2);
    }

    let imageColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let finalColor = mix(rainColor, imageColor, clamp(newVal, 0.0, 1.0));
    let alpha = clamp(newVal + charBright * 0.2 + bass * 0.05, 0.0, 1.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
