// ────────────────────────────────────────────────────────────────────────────────
//  Chromatic Folds Gemini – Fractalized Psychedelic Topology
//  Multi-layered folding, vortex manipulation, and enhanced color dynamics.
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
  config:      vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples:     array<vec4<f32>, 50>,
};

// --- (RGB/HSV, hash, mod functions - unchanged) ---
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

fn foldHue(h: f32, pivot: f32, strength: f32) -> f32 {
  let delta = h - pivot;
  return fract(pivot + sign(delta) * pow(abs(delta), strength));
}

fn hash2(p: vec2<f32>) -> f32 {
  var p2 = fract(p * vec2<f32>(123.456, 789.012));
  p2 = p2 + dot(p2, p2 + 45.678);
  return fract(p2.x * p2.y);
}

fn wrapMod(x: f32, y: f32) -> f32 {
  return x - y * floor(x / y);
}

// ✨ GEMINI UPGRADE: Vortex function
fn applyVortex(uv: vec2<f32>, center: vec2<f32>, strength: f32, time: f32) -> vec2<f32> {
    let diff = uv - center;
    let r = length(diff);
    let angle = atan2(diff.y, diff.x);
    let new_angle = angle + strength / (r + 0.1) * sin(r * 10.0 - time);
    return center + vec2<f32>(cos(new_angle), sin(new_angle)) * r;
}

// ───────────────────────────────────────────────────────────────────────────────
//  Main compute entry point
// ───────────────────────────────────────────────────────────────────────────────
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  let uv = vec2<f32>(gid.xy) / dims;
  let time = u.config.x;
  
  let foldStrength = u.zoom_params.x * 1.5 + 0.5;
  let pivotHue = u.zoom_params.y;
  let satScale = u.zoom_params.z * 0.5 + 0.75;
  let depthInfluence = u.zoom_params.w;
  let noiseAmount = u.zoom_config.x * 0.003;
  let feedbackStrength = u.zoom_config.y * 0.15 + 0.8;
  let rippleStrength = u.zoom_config.z * 0.005;
  let vortexStrength = u.zoom_params.x * 0.1; // Tied to fold strength

  let srcColor = textureSampleLevel(videoTex, videoSampler, uv, 0.0).rgb;
  let depthVal = textureSampleLevel(depthTex, depthSampler, uv, 0.0).r;

  // ✨ GEMINI UPGRADE: Apply vortex to UV
  var work_uv = applyVortex(uv, u.ripples[0].xy, vortexStrength, time);

  // ✨ GEMINI UPGRADE: Fractal folding (3 layers)
  var totalDisp = vec2<f32>(0.0);
  for (var i: i32 = 0; i < 3; i = i + 1) {
    let scale = pow(2.0, f32(i));
    let texel = 1.0 / (dims * scale);
    
    let h = rgb2hsv(textureSampleLevel(videoTex, videoSampler, work_uv * scale, 0.0).rgb).x;
    let hR = rgb2hsv(textureSampleLevel(videoTex, videoSampler, work_uv * scale + vec2<f32>(texel.x, 0.0), 0.0).rgb).x;
    let hL = rgb2hsv(textureSampleLevel(videoTex, videoSampler, work_uv * scale - vec2<f32>(texel.x, 0.0), 0.0).rgb).x;
    let hU = rgb2hsv(textureSampleLevel(videoTex, videoSampler, work_uv * scale + vec2<f32>(0.0, texel.y), 0.0).rgb).x;
    let hD = rgb2hsv(textureSampleLevel(videoTex, videoSampler, work_uv * scale - vec2<f32>(0.0, texel.y), 0.0).rgb).x;
    
    let gradX = wrapMod(hR - hL + 1.5, 1.0) - 0.5;
    let gradY = wrapMod(hU - hD + 1.5, 1.0) - 0.5;
    let hueGrad = vec2<f32>(gradX, gradY);
    
    let curvature = pow(depthVal, 2.0) * depthInfluence;
    totalDisp += hueGrad * foldStrength * 0.05 * (1.0 + curvature) / scale;
  }
  
  let noise = hash2(work_uv * 100.0 + time);
  let noiseDisp = vec2<f32>(sin(time + noise * 6.28), cos(time + noise * 6.28)) * noiseAmount;
  totalDisp += noiseDisp;
  
  // Enhanced ripple effect
  let rippleCount = u32(u.config.y);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let dist = distance(work_uv, r.xy);
    let t = time - r.z;
    if (t > 0.0 && t < 5.0) { // Longer decay
      let wave = sin(dist * 40.0 - t * 5.0) * sin(t * PI / 5.0);
      let amp = rippleStrength * (1.0 - dist) * pow(1.0 - t / 5.0, 2.0);
      if (dist > 0.001) {
        totalDisp += normalize(work_uv - r.xy) * wave * amp * 2.0;
      }
    }
  }

  let displacedUV = clamp(work_uv + totalDisp, vec2<f32>(0.0), vec2<f32>(1.0));
  let displacedColor = textureSampleLevel(videoTex, videoSampler, displacedUV, 0.0).rgb;
  
  var hsv = rgb2hsv(displacedColor);
  hsv.x = foldHue(hsv.x, pivotHue, foldStrength);
  // ✨ GEMINI UPGRADE: Secondary color shift
  hsv.x = fract(hsv.x + sin(time * 0.1) * 0.1);
  hsv.y = clamp(hsv.y * satScale, 0.0, 1.0);
  let foldedColor = hsv2rgb(hsv.x, hsv.y, hsv.z);

  let prev = textureSampleLevel(feedbackTex, videoSampler, uv, 0.0).rgb;
  let finalColor = mix(foldedColor, prev, feedbackStrength);
  
  textureStore(outTex, vec2<i32>(gid.xy), vec4<f32>(finalColor, 1.0));
  textureStore(outDepth, vec2<i32>(gid.xy), vec4<f32>(depthVal, 0.0, 0.0, 0.0));
  textureStore(feedbackOut, vec2<i32>(gid.xy), vec4<f32>(finalColor, 1.0));
}
