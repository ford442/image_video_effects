// ═══════════════════════════════════════════════════════════════════
//  Temporal Feedback Zoom Tracer
//  Category: post-processing
//  Features: mouse-driven, audio-reactive, temporal, history-ring,
//            upgraded-rgba, fbm-trail-jitter, chromatic-trail-separation,
//            mouse-driven-zoom-focus, noise-warp
//  Complexity: Medium
//  Upgraded: 2026-10-04 (prev 2026-06-28)
//  Ideas: nested monitor bezels streaming out of the zoom focus; recursion hue drift per feedback pass
//  A packing: display RGBA
//  Floor: history ring wraps at textureNumLayers (8, 4 or 1), not a
//         hardcoded 8 — see HISTORY RING DEPTH below
//  Requires: binding 13 (historyTexture — up to 8-layer ring buffer)
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

// Hue rotation about the grey axis (Rodrigues), applied once per feedback pass.
fn hueRotate(c: vec3<f32>, angle: f32) -> vec3<f32> {
  let k = vec3<f32>(0.57735027);
  let ca = cos(angle);
  return c * ca + cross(k, c) * sin(angle) + k * dot(k, c) * (1.0 - ca);
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
  let zp_x = u.zoom_params.x; let zp_y = u.zoom_params.y; let zp_z = u.zoom_params.z; let zp_w = u.zoom_params.w; let zp = clamp(vec4<f32>(zp_x, zp_y, zp_z, zp_w), vec4<f32>(0.0), vec4<f32>(1.0));
  let zoomFactor  = 1.0 + zp.x * 0.012 * (1.0 + bass * 0.5);
  let rotAngle    = (zp.y - 0.5) * 0.006 + mids * 0.001;
  let persistence = 0.92 + zp.z * 0.07;
  let blendAmt    = 0.05 + zp.w * 0.35;

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
  let warpedRaw = rotated / zoomFactor + focus + jitter;
  let warpedUV = clamp(warpedRaw, vec2<f32>(0.0), vec2<f32>(1.0));
  // Reads that leave the frame (rotation pushes corners out) fall to a dark surround
  // instead of HEAD's clamped edge smear.
  let edgeD = min(min(warpedRaw.x, 1.0 - warpedRaw.x), min(warpedRaw.y, 1.0 - warpedRaw.y));
  let inFrame = smoothstep(-0.002, 0.002, edgeD);

  // ── HISTORY RING DEPTH (floor fix, 2026-09-21) ───────────────────
  // The ring is at most 8 layers; after the VRAM probe the runtime may
  // allocate 8, 4 or 1, and it wraps its write head at the ALLOCATED
  // count (renderer/webgpu/frame.ts). A hardcoded HISTORY_DEPTH=8 asked
  // for layers that do not exist on a 4- or 1-layer device and WGSL
  // clamped them to the last layer: scrambled frame order, silently.
  let histDepth = max(textureNumLayers(historyTexture), 1u);
  let historyHead = u32(extraBuffer[4]);
  let layerPrev = (historyHead + histDepth - 1u) % histDepth;

  // Chromatic trail separation scales with zoom power
  let chromaShift = 0.001 + zp.x * 0.008;
  // Idea 2 — recursion hue drift: every pass rotates the history hue a little (mids widen
  // it), so the tunnel's depth layers walk through the spectrum like analog feedback.
  let hueStep = 0.035 + mids * 0.05;
  let histWarp = hueRotate(sampleHistoryChromatic(warpedUV, i32(layerPrev), chromaShift), hueStep) * inFrame
               + vec3<f32>(0.015) * (1.0 - inFrame);

  let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  // Blend: weighted history + current
  var output = mix(histWarp * persistence, current.rgb, blendAmt);

  // Idea 1 — nested monitor bezels: on a 3 Hz tick a thin bright bezel is injected at the
  // zoom focus; the zoom-in recursion carries each one outward (rotating with the warp), so
  // the tunnel fills with nested screens streaming toward the viewer.
  let aspect = res.x / max(res.y, 1.0);
  let bezelHalf = vec2<f32>(0.075 / aspect, 0.075) * (1.0 + bass * 0.25);
  let bq = abs(uv - focus) - bezelHalf;
  let bezelDist = abs(max(bq.x, bq.y));
  let bezelTick = 1.0 - smoothstep(0.0, 0.1, fract(time * 3.0));
  let bezel = (1.0 - smoothstep(0.0012, 0.0035, bezelDist)) * bezelTick * (0.35 + zp.x * 0.65);
  output = mix(output, vec3<f32>(0.92, 0.95, 1.0), bezel * 0.8);
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
    
    let clockRings = sin(length(uv - focus) * 95.0 - time * (5.0 + treble * 7.0));
    let spectral = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.094, 4.188) + clockRings * 3.0 + time * (0.8 + mids));

    let finalRGB = finalOut.rgb + spectral * (abs(clockRings) * 0.1 + clickFront * 0.25);
    textureStore(writeTexture, coord, vec4<f32>(finalRGB, finalOut.a));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, vec4<f32>(finalRGB, finalOut.a));
}
