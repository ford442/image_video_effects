// ────────────────────────────────────────────────────────────────────────────────
//  Chromatic Folds – mind‑bending psychedelic topology
//  Color as a physical dimension: each pixel is a point in 4‑D (x, y, depth, hue).
//  Warps image along local hue‑gradient, bends depth into curvature tensor.
// ────────────────────────────────────────────────────────────────────────────────
@group(0) @binding(0) var videoSampler: sampler;
@group(0) @binding(1) var videoTex:    texture_2d<f32>;
@group(0) @binding(2) var outTex:     texture_storage_2d<rgba32float, write>;

@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var depthTex:   texture_2d<f32>;
@group(0) @binding(5) var depthSampler: sampler;
@group(0) @binding(6) var outDepth:   texture_storage_2d<r32float, write>;

@group(0) @binding(7) var feedbackOut: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var normalBuf:   texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var feedbackTex: texture_2d<f32>;

@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var compSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;
// ────────────────────────────────────────────────────────────────────────────────

struct Uniforms {
  // config.x = time, config.y = rippleCount, config.zw = resolution.xy
  config:      vec4<f32>,
  // zoom_config.x = noise_amount, zoom_config.y = feedback_strength
  // zoom_config.z = ripple_strength, zoom_config.w = unused
  zoom_config: vec4<f32>,
  // zoom_params.x = fold_strength, zoom_params.y = hue_pivot
  // zoom_params.z = saturation_scale, zoom_params.w = depth_influence
  zoom_params: vec4<f32>,
  // ripple data: [x, y, startTime, unused] * 50
  ripples:     array<vec4<f32>, 50>,
};

// ───────────────────────────────────────────────────────────────────────────────
//  RGB ↔ HSV conversion
// ───────────────────────────────────────────────────────────────────────────────
fn rgb2hsv(c: vec3<f32>) -> vec3<f32> {
  let K = vec4<f32>(0.0, -1.0/3.0, 2.0/3.0, -1.0);
  let p = mix(vec4<f32>(c.b, c.g, K.w, K.z), vec4<f32>(c.g, c.b, K.x, K.y), step(c.b, c.g));
  let q = mix(vec4<f32>(p.x, p.y, p.w, c.r), vec4<f32>(c.r, p.y, p.z, p.x), step(p.x, c.r));
  let d = q.x - min(q.w, q.y);
  let e = 1.0e-10;
  return vec3<f32>(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
  let c = v * s;
  let h6 = h * 6.0;
  let x = c * (1.0 - abs(fract(h6) * 2.0 - 1.0));
  var rgb = vec3<f32>(0.0);
  if (h6 < 1.0)      { rgb = vec3<f32>(c, x, 0.0); }
  else if (h6 < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
  else if (h6 < 3.0) { rgb = vec3<f32>(0.0, c, x); }
  else if (h6 < 4.0) { rgb = vec3<f32>(0.0, x, c); }
  else if (h6 < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
  else               { rgb = vec3<f32>(c, 0.0, x); }
  return rgb + vec3<f32>(v - c);
}

// ───────────────────────────────────────────────────────────────────────────────
//  Fold the hue around a pivot – creates the "fold" effect
// ───────────────────────────────────────────────────────────────────────────────
fn foldHue(h: f32, pivot: f32, strength: f32) -> f32 {
  let delta = h - pivot;
  return fract(pivot + sign(delta) * pow(abs(delta), strength));
}

// ───────────────────────────────────────────────────────────────────────────────
//  Simple 2‑D noise (hash)
// ───────────────────────────────────────────────────────────────────────────────
fn hash2(p: vec2<f32>) -> f32 {
  var p2 = fract(p * vec2<f32>(123.456, 789.012));
  p2 = p2 + dot(p2, p2 + 45.678);
  return fract(p2.x * p2.y);
}

// ───────────────────────────────────────────────────────────────────────────────
//  Wrap-around modulo for hue gradients
// ───────────────────────────────────────────────────────────────────────────────
fn wrapMod(x: f32, y: f32) -> f32 {
  return x - y * floor(x / y);
}

// ───────────────────────────────────────────────────────────────────────────────
//  Main compute entry point
// ───────────────────────────────────────────────────────────────────────────────
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dimsI = textureDimensions(videoTex);
  let dims = vec2<f32>(f32(dimsI.x), f32(dimsI.y));
  if (gid.x >= u32(dimsI.x) || gid.y >= u32(dimsI.y)) {
    return;
  }

  let uv = vec2<f32>(gid.xy) / dims;
  let texel = 1.0 / dims;
  let time = u.config.x;

  // ──────────────────────────────────────────────────────────────────────────
  //  Parameters
  // ──────────────────────────────────────────────────────────────────────────
  let foldStrength = u.zoom_params.x * 1.5 + 0.5;           // 0.5 - 2.0
  let pivotHue = u.zoom_params.y;                            // 0 - 1
  let satScale = u.zoom_params.z * 0.5 + 0.75;              // 0.75 - 1.25
  let depthInfluence = u.zoom_params.w;                      // 0 - 1
  let noiseAmount = u.zoom_config.x * 0.003;                 // noise displacement
  let feedbackStrength = u.zoom_config.y * 0.15 + 0.8;      // 0.8 - 0.95
  let rippleStrength = u.zoom_config.z * 0.005;             // ripple amplitude

  // ──────────────────────────────────────────────────────────────────────────
  //  1. Read source color & depth
  // ──────────────────────────────────────────────────────────────────────────
  let srcColor = textureSampleLevel(videoTex, videoSampler, uv, 0.0).rgb;
  let depthVal = textureSampleLevel(depthTex, depthSampler, uv, 0.0).r;

  // ──────────────────────────────────────────────────────────────────────────
  //  2. Compute local hue gradient (finite differences)
  // ──────────────────────────────────────────────────────────────────────────
  let h = rgb2hsv(srcColor).x;
  let hR = rgb2hsv(textureSampleLevel(videoTex, videoSampler, uv + vec2<f32>(texel.x, 0.0), 0.0).rgb).x;
  let hL = rgb2hsv(textureSampleLevel(videoTex, videoSampler, uv - vec2<f32>(texel.x, 0.0), 0.0).rgb).x;
  let hU = rgb2hsv(textureSampleLevel(videoTex, videoSampler, uv + vec2<f32>(0.0, texel.y), 0.0).rgb).x;
  let hD = rgb2hsv(textureSampleLevel(videoTex, videoSampler, uv - vec2<f32>(0.0, texel.y), 0.0).rgb).x;

  // Wrap‑around gradient (handle hue discontinuity at 0/1)
  let gradX = wrapMod(hR - hL + 1.5, 1.0) - 0.5;
  let gradY = wrapMod(hU - hD + 1.5, 1.0) - 0.5;
  let hueGrad = vec2<f32>(gradX, gradY);

  // ──────────────────────────────────────────────────────────────────────────
  //  3. Depth curvature – treat depth as a curvature tensor
  // ──────────────────────────────────────────────────────────────────────────
  let curvature = pow(depthVal, 2.0) * depthInfluence;

  // ──────────────────────────────────────────────────────────────────────────
  //  4. Ambient "fold" displacement
  // ──────────────────────────────────────────────────────────────────────────
  // Map hue gradient to a displacement vector in screen space
  let dispBase = hueGrad * foldStrength * 0.05 * (1.0 + curvature);

  // Add subtle noise to the displacement
  let noise = hash2(uv * 100.0 + time);
  let noiseDisp = vec2<f32>(
    sin(time + noise * 6.28318),
    cos(time + noise * 6.28318)
  ) * noiseAmount;

  var totalDisp = dispBase + noiseDisp;

  // ──────────────────────────────────────────────────────────────────────────
  //  5. Ripple effect (click-driven)
  // ──────────────────────────────────────────────────────────────────────────
  let rippleCount = u32(u.config.y);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let dist = distance(uv, r.xy);
    let t = time - r.z;
    if (t > 0.0 && t < 3.0) {
      let wave = sin(dist * 30.0 - t * 4.0);
      let amp = rippleStrength * (1.0 - dist) * (1.0 - t / 3.0);
      if (dist > 0.001) {
        totalDisp = totalDisp + normalize(uv - r.xy) * wave * amp;
      }
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  6. Sample displaced UV for color
  // ──────────────────────────────────────────────────────────────────────────
  let displacedUV = clamp(uv + totalDisp, vec2<f32>(0.0), vec2<f32>(1.0));
  let displacedColor = textureSampleLevel(videoTex, videoSampler, displacedUV, 0.0).rgb;

  // ──────────────────────────────────────────────────────────────────────────
  //  7. Fold the hue of the sampled color
  // ──────────────────────────────────────────────────────────────────────────
  var hsv = rgb2hsv(displacedColor);
  hsv.x = foldHue(hsv.x, pivotHue, foldStrength);
  hsv.y = clamp(hsv.y * satScale, 0.0, 1.0);
  let foldedColor = hsv2rgb(hsv.x, hsv.y, hsv.z);

  // ──────────────────────────────────────────────────────────────────────────
  //  8. Feedback: blend with previous frame
  // ──────────────────────────────────────────────────────────────────────────
  let prev = textureSampleLevel(feedbackTex, videoSampler, uv, 0.0).rgb;
  let finalColor = mix(foldedColor, prev, feedbackStrength);

  // ──────────────────────────────────────────────────────────────────────────
  //  9. Write outputs
  // ──────────────────────────────────────────────────────────────────────────
  textureStore(outTex, gid.xy, vec4<f32>(finalColor, 1.0));
  textureStore(outDepth, gid.xy, vec4<f32>(depthVal, 0.0, 0.0, 0.0));
  textureStore(feedbackOut, gid.xy, vec4<f32>(finalColor, 1.0));
}
