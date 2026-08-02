// ═══════════════════════════════════════════════════════════════════
//  Sonic Boom v3
//  Category: distortion
//  Features: mouse-driven, audio-reactive, mach-cone, prandtl-glauert,
//            shock-diamonds, condensation-fog, aces-tone-map,
//            sprung-shock-center, click-mach-bursts, per-ring-fft
//  Complexity: High
//  Upgraded: 2026-08-02 (Batch 29)
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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=RingRadius, y=RingWidth, z=Distortion, w=ChromSplit
  ripples: array<vec4<f32>, 50>,
};

// Slider contract (shader_definitions/distortion/sonic-boom.json — ids/defaults locked):
//   P1 x = Ring Radius  (0..1,      default 0.2)  -> mach-cone radius
//   P2 y = Ring Width   (0.01..0.2, default 0.05) -> ring gaussian half-width
//   P3 z = Distortion   (0..1,      default 0.5)  -> mach push + refraction amp
//   P4 w = Chrom. Split (0..0.1,    default 0.02) -> doppler chromatic spread
//
// Sprung shock center lives in extraBuffer[133..137]:
//   [133..134] = spring position (eased mouse / shock origin)
//   [135..136] = spring velocity
//   [137]      = initialized flag
// extraBuffer[0..4] is reserved and [5..132] belongs to the engine FFT,
// so persistent shader state stays in [133..255] only.

fn aces_tonemap(x: vec3<f32>) -> vec3<f32> {
  let a = vec3<f32>(2.51);
  let b = vec3<f32>(0.03);
  let c = vec3<f32>(2.43);
  let d = vec3<f32>(0.59);
  let e = vec3<f32>(0.14);
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

const PHI: f32 = 1.61803398874989484820;

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }
  let dim = vec2<i32>(i32(u.config.z), i32(u.config.w));
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(coord) / vec2<f32>(f32(dim.x), f32(dim.y));
  let aspect = vec2<f32>(f32(dim.x) / f32(dim.y), 1.0);

  let bass   = plasmaBuffer[0].x;
  let mids   = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Per-ring FFT voices: each PHI ring rides its own spectral bin (±20% amp).
  let voice0 = plasmaBuffer[2].x;
  let voice1 = plasmaBuffer[4].x;
  let voice2 = plasmaBuffer[6].x;

  let radius   = u.zoom_params.x;
  let width    = u.zoom_params.y;
  let strength = u.zoom_params.z * (1.0 + bass * 0.6);
  let split    = u.zoom_params.w;

  let mouse_pos = u.zoom_config.yz;

  // Sprung shock center: a critically-damped spring chases the raw mouse
  // (raw mouse stays the spring target), so the mach cone trails the cursor
  // like a jet that can't turn instantly. Every invocation computes the same
  // local step; thread (0,0) persists it for the next frame.
  let springK = 48.0;
  let springDamp = 2.0 * sqrt(springK); // critical damping
  let springDt = 0.016;
  var sPos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  var sVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
  if (extraBuffer[137] < 0.5) {
    sPos = mouse_pos; // wake up on the mouse, not the corner
    sVel = vec2<f32>(0.0);
  }
  let sAccel = (mouse_pos - sPos) * springK - sVel * springDamp;
  sVel = sVel + sAccel * springDt;
  sPos = sPos + sVel * springDt;
  if (global_id.x == 0u && global_id.y == 0u) {
    extraBuffer[133] = sPos.x;
    extraBuffer[134] = sPos.y;
    extraBuffer[135] = sVel.x;
    extraBuffer[136] = sVel.y;
    extraBuffer[137] = 1.0;
  }
  let shock_pos = sPos;

  let to_pixel = (uv - shock_pos) * aspect; // aspect correction preserved
  let dist = length(to_pixel);
  let dir = to_pixel / max(dist, 1e-4);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let atmDensity = 0.5 + depth * 0.5;

  let machNum = 0.8 + strength * 1.4 + bass * 0.4;
  let machAngle = asin(clamp(1.0 / max(machNum, 1.001), 0.0, 1.0));
  let coneDist = abs(dist - radius) / max(machAngle, 0.01);

  let widthHalf = max(width * 0.5, 1e-4);
  let invWH = 1.0 / widthHalf;
  let d0 = (dist - radius) * invWH;
  let d1 = (dist - radius / PHI) * invWH;
  let d2 = (dist - radius / (PHI * PHI)) * invWH;
  let ring0 = exp(-d0 * d0 * 4.0) * (0.8 + 0.4 * voice0);
  let ring1 = exp(-d1 * d1 * 6.0) * 0.55 * (0.8 + 0.4 * voice1);
  let ring2 = exp(-d2 * d2 * 8.0) * 0.30 * (0.8 + 0.4 * voice2);
  var ringSum = ring0 + ring1 + ring2;

  // Click mach bursts: each live ripple fires a secondary expanding shock
  // ring from its click point (radius grows at mach speed ~0.5/s, strength
  // decays as exp(-age * 1.5), ~2s life), composed into ringSum before the
  // distortion taps so clicks launch their own sonic booms.
  let rippleCount = min(u32(u.config.y), 50u);
  var burstSum = 0.0;
  var burstDir = vec2<f32>(0.0);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let rippleAge = u.config.x - ripple.z;
    if (rippleAge >= 0.0 && rippleAge < 2.0) {
      let rVec = (uv - ripple.xy) * aspect;
      let rDist = length(rVec);
      let burstRadius = rippleAge * 0.5;      // expanding at mach speed
      let burstFade = exp(-rippleAge * 1.5);  // ~2s boom lifetime
      let dB = (rDist - burstRadius) * invWH;
      let burstRing = exp(-dB * dB * 4.0) * burstFade; // same ring0 gaussian form
      if (burstRing > burstSum) {
        burstSum = burstRing;
        burstDir = rVec / max(rDist, 1e-4);
      }
    }
  }
  ringSum = min(ringSum + burstSum, 2.5);

  let diamondPhase = sin(coneDist * 12.0 * PHI) * 0.5 + 0.5;
  let shockDiamond = diamondPhase * ring0 * 0.4 * select(0.0, 1.0, machNum > 1.0);

  let condensation = exp(-coneDist * coneDist * 2.0) * atmDensity * (0.3 + bass * 0.4) * select(0.0, 1.0, machNum > 0.95);
  let fogScatter = condensation * 0.5 * (1.0 + mids * 0.5);

  let prevTail = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).r;
  let ringFinal = max(ringSum, prevTail * 0.82);

  // The strongest click burst pushes radially from its own launch point;
  // the main PHI stack and temporal tail retain the sprung shock direction.
  let mainWeight = max(ringFinal - burstSum, 0.0);
  let flow = dir * mainWeight + burstDir * burstSum;
  let flowDir = flow / max(length(flow), 1e-4);
  let distortion = flowDir * ringFinal * strength * 0.12 * (1.0 + mids * 0.3);
  let velocity = ringFinal * strength * (1.0 + bass * 0.5);
  let caStrength = split * (1.0 + velocity * 3.0);
  let doppler = (ring0 - ring2) * split * 10.0;

  let uv_r = clamp(uv - distortion * (1.0 + caStrength * 1.5 + doppler), vec2<f32>(0.0), vec2<f32>(1.0));
  let uv_g = clamp(uv - distortion, vec2<f32>(0.0), vec2<f32>(1.0));
  let uv_b = clamp(uv - distortion * (1.0 - caStrength * 1.5 - doppler), vec2<f32>(0.0), vec2<f32>(1.0));

  let c = textureSampleLevel(readTexture, u_sampler, uv_g, 0.0);
  let r = textureSampleLevel(readTexture, u_sampler, uv_r, 0.0).r;
  let b = textureSampleLevel(readTexture, u_sampler, uv_b, 0.0).b;

  let shockFront = ring0 * (0.6 + treble * 0.4) + burstSum * 0.25;
  let bloom = vec3<f32>(0.9, 0.95, 1.0) * shockFront * 0.35;
  let diamondColor = vec3<f32>(0.6, 0.8, 1.0) * shockDiamond * (1.0 + treble * 0.5);
  let fogColor = vec3<f32>(0.85, 0.88, 0.92) * fogScatter;

  var finalColor = vec3<f32>(r, c.g, b);
  finalColor = finalColor + bloom + diamondColor + fogColor;
  finalColor = aces_tonemap(finalColor * (1.0 + shockFront * 0.3));

  let shockIntensity = clamp(ringSum + shockDiamond + shockFront * 0.5, 0.0, 1.0);
  let alpha = clamp(shockIntensity * condensation * depth * 1.2 + abs(doppler) * 0.4 + treble * 0.06, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
  textureStore(dataTextureA, global_id.xy, vec4<f32>(finalColor, alpha));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
