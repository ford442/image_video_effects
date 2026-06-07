// ═══════════════════════════════════════════════════════════════════
//  VHS Chroma Bleed
//  Category: retro-glitch
//  Features: mouse-driven, audio-reactive, jitter-smear, chromatic-bleed, depth-scatter, upgraded-rgba
//  Complexity: High
//  Chunks From: vhs-chroma-bleed, hash, bass_env
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

fn hash22(p: vec2<f32>) -> vec2<f32> {
  let h1 = hash21(p);
  let h2 = hash21(p + vec2<f32>(1.0, 0.0));
  return vec2<f32>(h1, h2);
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
    let depthScatter = mix(0.7, 1.3, depth);

    let bleedStrength = u.zoom_params.x * bass_env(bass, mids);
    let jitterAmt = u.zoom_params.y;
    let driftSpeed = u.zoom_params.z;
    let rgbShift = u.zoom_params.w * depthScatter;

    // Audio-reactive jitter: bass drives line dropout, treble adds micro-jitter
    let lineHash = hash21(vec2<f32>(0.0, uv.y * resolution.y));
    let dropOut = step(1.0 - bass * 0.15, lineHash);
    let microJitter = (hash21(vec2<f32>(time * 100.0, uv.y * 500.0)) - 0.5) * jitterAmt * (1.0 + treble);

    let dToMouse = uv - mousePos;
    let lenD = length(dToMouse);
    let safeDir = select(vec2<f32>(0.0), dToMouse / max(lenD, 0.0001), lenD > 0.001);
    let mouseDist = length(dToMouse);
    let mouseForce = smoothstep(0.3, 0.0, mouseDist) * 0.05;

    let jitter = microJitter + safeDir.y * mouseForce;
    let drift = sin(uv.y * 20.0 + time * driftSpeed * 5.0) * 0.005 * depthScatter;
    let bleed = (dropOut * 0.02) + bleedStrength * (0.02 + drift) * depthScatter;

    // Chromatic bleed: R and B shift in opposite directions
    let rOff = clamp(uv + vec2<f32>(-bleed * (1.0 + rgbShift), jitter), vec2<f32>(0.0), vec2<f32>(1.0));
    let bOff = clamp(uv + vec2<f32>(bleed * (1.0 + rgbShift), -jitter), vec2<f32>(0.0), vec2<f32>(1.0));
    let gOff = clamp(uv + vec2<f32>(0.0, jitter * 0.5), vec2<f32>(0.0), vec2<f32>(1.0));

    let r = textureSampleLevel(readTexture, u_sampler, rOff, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, gOff, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, bOff, 0.0).b;

    // Mids add color flash during chroma shifts
    let flash = mids * 0.08 * bleed * 10.0;
    let rgb = vec3<f32>(r, g, b) + vec3<f32>(flash, flash * 0.5, flash * 0.2);

    let alpha = clamp((r + g + b) * 0.3 + bleed * 5.0 + bass * 0.05, 0.0, 1.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(rgb, alpha));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(rgb, alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
