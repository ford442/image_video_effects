// ═══════════════════════════════════════════════════════════════════
//  Temporal Feedback Zoom Tracer
//  Category: post-processing
//  Features: mouse-driven, audio-reactive, temporal, history-ring,
//            upgraded-rgba, fbm-trail-jitter, chromatic-trail-separation,
//            mouse-driven-zoom-focus, noise-warp
//  Complexity: Medium
//  Upgraded: 2026-06-28
//  Requires: binding 13 (historyTexture — HISTORY_DEPTH=8 ring buffer)
//
//  Reads the most recent history frame through an affine warp
//  (zoom + rotation centred on mouse or canvas centre) then blends it
//  with the current frame.  FBM jitter and chromatic RGB separation are
//  applied to the history trail, while mouse position controls the
//  zoom focus point and audio bass adds zoom energy.
//
//  zoom_params layout:
//    x = zoom power       (0→1.0×, 1→1.012×)
//    y = rotation         (0→-0.003rad, 1→+0.003rad)
//    z = persistence      (0→0.92, 1→0.99)
//    w = current blend    (0→0.05, 1→0.40)
//
//  extraBuffer layout:
//    [0]=bass  [1]=mid  [2]=treble  [3]=reserved  [4]=historyHead
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
@group(0) @binding(13) var historyTexture: texture_2d_array<f32>;

struct Uniforms {
  config: vec4<f32>,      // x=time, y=rippleCount, z=resX, w=resY
  zoom_config: vec4<f32>, // x=time, y=mouseX, z=mouseY, w=mouseDown
  zoom_params: vec4<f32>, // x=zoom, y=rotation, z=persistence, w=blend
  ripples: array<vec4<f32>, 50>,
};

const HISTORY_DEPTH: u32 = 8u;
const PI: f32 = 3.14159265358979323846;

// ── Hash & FBM noise ─────────────────────────────────────────────
fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let a = hash21(i);
  let b = hash21(i + vec2<f32>(1.0, 0.0));
  let c = hash21(i + vec2<f32>(0.0, 1.0));
  let d = hash21(i + vec2<f32>(1.0, 1.0));
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var sum = 0.0;
  var amp = 0.5;
  var freq = 1.0;
  for (var i = 0; i < octaves; i = i + 1) {
    sum = sum + amp * valueNoise(p * freq);
    freq = freq * 2.0;
    amp = amp * 0.5;
  }
  return sum;
}

fn rgbToLuma(rgb: vec3<f32>) -> f32 {
  return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

// ── Chromatic history sample ─────────────────────────────────────
fn sampleHistoryChromatic(uv: vec2<f32>, layer: i32, shift: f32) -> vec3<f32> {
  let r = textureSampleLevel(historyTexture, u_sampler, uv + vec2<f32>(shift, 0.0), layer, 0.0).r;
  let g = textureSampleLevel(historyTexture, u_sampler, uv, layer, 0.0).g;
  let b = textureSampleLevel(historyTexture, u_sampler, uv - vec2<f32>(shift, 0.0), layer, 0.0).b;
  return vec3<f32>(r, g, b);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res   = vec2<f32>(u.config.z, u.config.w);
  let coord = vec2<i32>(global_id.xy);
  if (coord.x >= i32(res.x) || coord.y >= i32(res.y)) { return; }

  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Clamp and normalize params
  let zp = clamp(u.zoom_params, vec4<f32>(0.0), vec4<f32>(1.0));
  let zoomFactor  = 1.0 + u.zoom_params.x * 0.012 * (1.0 + bass * 0.5);
  let rotAngle    = (u.zoom_params.y - 0.5) * 0.006 + mids * 0.001;
  let persistence = 0.92 + u.zoom_params.z * 0.07;
  let blendAmt    = 0.05 + u.zoom_params.w * 0.35;

  // Mouse-driven zoom focus (defaults to centre when mouse at 0.5)
  let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let focus = mix(vec2<f32>(0.5), mouse, 0.7);

  // FBM trail jitter evolves slowly with time
  let noiseUV = uv * 8.0 + time * 0.15;
  let jitterStrength = 0.003 + zp.x * 0.006;
  let jitter = vec2<f32>(
    fbm(noiseUV + vec2<f32>(0.0, 12.34), 3) - 0.5,
    fbm(noiseUV + vec2<f32>(56.78, 0.0), 3) - 0.5,
  ) * jitterStrength * (1.0 + bass * 0.5);

  // Affine warp: zoom + rotation about focus point
  let uvC = uv - focus;
  let cosR = cos(rotAngle);
  let sinR = sin(rotAngle);
  let rotated = vec2<f32>(
    cosR * uvC.x - sinR * uvC.y,
    sinR * uvC.x + cosR * uvC.y,
  );
  let warpedUV = clamp(rotated / zoomFactor + focus + jitter, vec2<f32>(0.0), vec2<f32>(1.0));

  let historyHead = u32(extraBuffer[4]);
  let layerPrev = (historyHead + HISTORY_DEPTH - 1u) % HISTORY_DEPTH;

  // Chromatic trail separation scales with zoom power
  let chromaShift = 0.001 + zp.x * 0.008;
  let histWarp = sampleHistoryChromatic(warpedUV, i32(layerPrev), chromaShift);

  let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  // Blend: weighted history + current
  let output = mix(histWarp * persistence, current.rgb, blendAmt);
  let motionMag = length(histWarp - current.rgb);

  // Preserve input alpha, adding motion-driven echo alpha
  let alpha = clamp(current.a * 0.6 + motionMag * 4.0 + bass * 0.25 + 0.25, 0.0, 1.0);
  let finalOut = vec4<f32>(output, alpha);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  
    var clickFront = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let event = u.ripples[i];
        let age = max(time - event.z, 0.0);
        clickFront += exp(-age * 1.8) * exp(-abs(length((uv - event.xy) * vec2<f32>(u.config.z/u.config.w, 1.0)) - age * 0.38) * 58.0);
    }
    
    let clockRings = sin(length(uv - vec2<f32>(0.5)) * 95.0 - time * (5.0 + treble * 7.0));
    let spectral = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.094, 4.188) + clockRings * 3.0 + time * (0.8 + mids));

    let __finalRGB = finalOut.rgb + spectral * (abs(clockRings) * 0.1 + clickFront * 0.25);
    textureStore(writeTexture, coord, vec4<f32>(__finalRGB, finalOut.a));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, vec4<f32>(__finalRGB, finalOut.a));
}
