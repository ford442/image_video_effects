// ═══════════════════════════════════════════════════════════════════
//  Cyber Scan
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive, temporal-scan-pass, depth-colorize, chromatic-scan, upgraded-rgba
//  Complexity: High
//  Chunks From: cyber-scan, bass_env
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
    let mousePos = u.zoom_config.yz;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthColorize = mix(0.5, 1.5, depth);

    let scanSpeed = u.zoom_params.x * bass_env(bass, mids);
    let trailLength = u.zoom_params.y;
    let scanWidth = u.zoom_params.z;
    let colorShiftAmt = u.zoom_params.w;

    let scanLine = fract(mousePos.x + time * scanSpeed);
    let dist = abs(uv.x - scanLine);

    let w = scanWidth * (1.0 + bass * 0.3);
    let intensity = smoothstep(w, 0.0, dist);
    let trail = smoothstep(w * 5.0, w, dist) * trailLength;

    // Temporal scan: previous pass smears vertically
    let prev = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
    let smear = mix(prev.rgb * 0.85, vec3<f32>(0.0), 0.15);

    let sourceColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let luma = dot(sourceColor.rgb, vec3<f32>(0.2126, 0.7152, 0.0722));

    // Depth colorize: near objects get warm scan, far objects get cool scan
    let nearHue = 0.02;   // warm orange
    let farHue = 0.55;    // cool cyan
    let hue = mix(farHue, nearHue, depth);
    let k = vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0);
    let p = abs(fract(vec3<f32>(hue) + k) * 6.0 - vec3<f32>(3.0));
    let scanColor = vec3<f32>(0.9, 0.85, 0.8) * mix(vec3<f32>(1.0), clamp(p - vec3<f32>(1.0), vec3<f32>(0.0), vec3<f32>(1.0)), 0.7);

    // Chromatic scan: treble shifts RGB channels horizontally
    let chroma = colorShiftAmt * treble * 0.02;
    let rUV = clamp(uv + vec2<f32>(chroma, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let bUV = clamp(uv - vec2<f32>(chroma, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
    let g = sourceColor.g;

    let chromaSource = vec3<f32>(r, g, b);
    var rgb = mix(chromaSource, scanColor, intensity * 0.5);
    rgb = mix(rgb, smear, trail * 0.3);
    rgb = rgb + scanColor * intensity * 0.8 * depthColorize;

    let alpha = clamp(intensity + trail * 0.2 + bass * 0.05, 0.0, 1.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(rgb, alpha));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(rgb, alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
