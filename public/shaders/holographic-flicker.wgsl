// ═══════════════════════════════════════════════════════════════════
//  Holographic Flicker
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive, temporal-flicker, depth-rainbow, chromatic-ghosting, upgraded-rgba
//  Complexity: High
//  Chunks From: holographic-flicker, hash, bass_env
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

fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
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
    let mousePos = u.zoom_config.yz;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthHue = mix(0.0, 1.0, depth);

    let flickerSpeed = u.zoom_params.x * bass_env(bass, mids);
    let glitchAmt = u.zoom_params.y;
    let hologramIntensity = u.zoom_params.z;
    let ghostAmt = u.zoom_params.w;

    let dToMouse = uv - mousePos;
    let mouseDist = length(dToMouse);
    let mouseInfluence = smoothstep(0.4, 0.0, mouseDist);

    // Temporal ghosting: previous frame offset by velocity
    let prev = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
    let ghost = prev * 0.7 * ghostAmt;

    // Audio-reactive flicker: bass drives blackout probability, treble drives micro-glitch
    let flicker = hash21(vec2<f32>(floor(time * flickerSpeed * 10.0), uv.y * resolution.y));
    let blackout = step(1.0 - bass * 0.2, flicker) * 0.5;
    let microGlitch = (hash21(vec2<f32>(time * 500.0, uv.y * 2000.0)) - 0.5) * glitchAmt * treble * 0.02;

    let sourceColor = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(microGlitch, 0.0), 0.0);
    let luma = dot(sourceColor.rgb, vec3<f32>(0.2126, 0.7152, 0.0722));

    // Depth rainbow: hue shifts with depth + bass
    let hue = fract(depthHue + time * 0.05 + bass * 0.1 + mouseInfluence * 0.1);
    let k = vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0);
    let p = abs(fract(vec3<f32>(hue) + k) * 6.0 - vec3<f32>(3.0));
    let rainbow = clamp(p - vec3<f32>(1.0), vec3<f32>(0.0), vec3<f32>(1.0));

    // Chromatic ghosting: R and B from different temporal offsets
    let rGhost = textureSampleLevel(dataTextureC, non_filtering_sampler, uv + vec2<f32>(ghostAmt * 0.01, 0.0), 0.0).r;
    let bGhost = textureSampleLevel(dataTextureC, non_filtering_sampler, uv - vec2<f32>(ghostAmt * 0.01, 0.0), 0.0).b;
    let gGhost = ghost.g;

    let hologram = vec3<f32>(rGhost, gGhost, bGhost) * (0.5 + luma * 0.5) + rainbow * hologramIntensity * 0.3;
    let rgb = mix(sourceColor.rgb + hologram, vec3<f32>(0.0), blackout);

    let alpha = clamp(luma * 0.8 + hologramIntensity * 0.2 + bass * 0.05, 0.0, 1.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(rgb, alpha));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(rgb, alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
