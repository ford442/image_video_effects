// ═══════════════════════════════════════════════════════════════════
//  Temporal RGB Smear — Interactivist Upgrade
//  Category: image
//  Features: mouse-driven, audio-reactive, temporal, click-burst
//  Complexity: Medium
//  Chunks From: temporal-rgb-smear (original)
//  Created: 2026-05-02
//  By: Interactivist Agent
// ═══════════════════════════════════════════════════════════════════

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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=GreenLag, y=BlueLag, z=Feedback, w=Gravity
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;

  // Audio input: bass, mids, treble
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Parameters
  let greenLag = mix(0.1, 0.95, u.zoom_params.x);
  let blueLag = mix(0.2, 0.98, u.zoom_params.y);
  let feedback = u.zoom_params.z;
  let gravity = u.zoom_params.w;

  // Mouse velocity tracking via extraBuffer
  let prevMouse = vec2<f32>(extraBuffer[0], extraBuffer[1]);
  let mouseVel = mouse - prevMouse;
  let mouseSpeed = length(mouseVel);
  extraBuffer[0] = mouse.x;
  extraBuffer[1] = mouse.y;

  // Gravity well — UVs pulled toward mouse, intensified by bass
  let toMouse = mouse - uv;
  let distMouse = length(toMouse);
  let gravStrength = gravity * 0.05 * (1.0 + bass * 2.0);
  let gravityUV = uv + toMouse * gravStrength / (distMouse + 0.15);

  // Motion trail — UV offset opposite to fast mouse movement
  let trailUV = uv - mouseVel * mouseSpeed * 3.0;

  // Blend UVs: gravity dominates near mouse, trail when moving fast
  let gravWeight = smoothstep(0.5, 0.0, distMouse);
  let trailWeight = smoothstep(0.0, 0.12, mouseSpeed);
  var sampleUV = mix(uv, gravityUV, gravWeight);
  sampleUV = mix(sampleUV, trailUV, trailWeight);

  // Ripple shockwaves from mouse clicks
  let rippleCount = u32(u.config.y);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let rPos = r.xy;
    let rAge = time - r.z;
    let rDist = distance(uv, rPos);
    let wave = sin(rDist * 50.0 - rAge * 10.0) * exp(-rAge * 3.0) * exp(-rDist * 4.0);
    sampleUV += vec2<f32>(wave) * 0.03 * (1.0 + mouseDown);
  }

  // Depth-based parallax — foreground smears less than background
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthFactor = mix(1.0, 0.3, depth);

  // Audio-modulated lag with depth factor
  let gLag = clamp(greenLag * (0.7 + mids * 0.4) * depthFactor, 0.0, 0.99);
  let bLag = clamp(blueLag * (0.7 + bass * 0.4) * depthFactor, 0.0, 0.99);

  // Sample current frame at displaced UV
  let current = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);

  // Read history: R=greenHistory, G=blueHistory, B=prevOutG, A=prevOutB
  let history = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);

  // Temporal accumulation
  let newGreenHistory = mix(current.g, history.r, gLag);
  let newBlueHistory = mix(current.b, history.g, bLag);

  // Feedback loop — blend with previous output, driven by bass
  let fb = feedback * (1.0 + bass * 0.3);
  let finalG = mix(newGreenHistory, history.b, fb * 0.6);
  let finalB = mix(newBlueHistory, history.a, fb * 0.6);

  // Treble sparkle near mouse
  let sparkle = treble * 0.25 * smoothstep(0.4, 0.0, distMouse);
  let outputColor = vec4<f32>(current.r + sparkle, finalG, finalB, current.a);

  // Store history + feedback state for next frame
  textureStore(dataTextureA, global_id.xy,
    vec4<f32>(newGreenHistory, newBlueHistory, finalG, finalB));

  // Write to screen
  textureStore(writeTexture, vec2<i32>(global_id.xy), outputColor);

  // Pass through depth
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
