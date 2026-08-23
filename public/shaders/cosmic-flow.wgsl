// ═══════════════════════════════════════════════════════════════════
//  Cosmic Flow Pro — braided magnetohydrodynamic nebula currents
//  A owns pre-tonemap display history; C is the exact previous A copy.
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

const TAU: f32 = 6.28318530718;

fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let cell = floor(p);
  let f = fract(p);
  let w = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
  return mix(
    mix(hash21(cell), hash21(cell + vec2<f32>(1.0, 0.0)), w.x),
    mix(hash21(cell + vec2<f32>(0.0, 1.0)), hash21(cell + vec2<f32>(1.0, 1.0)), w.x),
    w.y
  );
}

fn fbm(p0: vec2<f32>) -> f32 {
  var p = p0;
  var sum = 0.0;
  var amplitude = 0.52;
  let spin = mat2x2<f32>(0.87758, -0.47943, 0.47943, 0.87758);
  for (var octave = 0; octave < 5; octave += 1) {
    sum += amplitude * valueNoise(p);
    p = spin * p * 2.03 + vec2<f32>(17.1, 9.2);
    amplitude *= 0.5;
  }
  return sum;
}

fn curlField(p: vec2<f32>, t: f32) -> vec2<f32> {
  let e = 0.018;
  let drift = vec2<f32>(t * 0.13, -t * 0.09);
  let dx = fbm(p + drift + vec2<f32>(e, 0.0)) - fbm(p + drift - vec2<f32>(e, 0.0));
  let dy = fbm(p + drift + vec2<f32>(0.0, e)) - fbm(p + drift - vec2<f32>(0.0, e));
  return vec2<f32>(dy, -dx) / (2.0 * e);
}

fn cosinePalette(t: f32, shift: f32) -> vec3<f32> {
  let phase = vec3<f32>(0.03, 0.19, 0.38) + shift;
  return vec3<f32>(0.48, 0.42, 0.56)
    + vec3<f32>(0.46, 0.48, 0.42) * cos(TAU * (vec3<f32>(0.82, 0.91, 1.03) * t + phase));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn clampPixel(pixel: vec2<i32>, dims: vec2<i32>) -> vec2<i32> {
  return clamp(pixel, vec2<i32>(0), dims - vec2<i32>(1));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let pixel = vec2<i32>(gid.xy);
  let dims = vec2<i32>(resolution);
  let uv = (vec2<f32>(gid.xy) + 0.5) / resolution;
  let aspect = resolution.x / resolution.y;
  let aspectVec = vec2<f32>(aspect, 1.0);
  let centered = (uv - 0.5) * aspectVec;
  let time = u.config.x;

  // Saved-preset contract: speed, scale, intensity, color_shift.
  let speed = mix(0.08, 0.72, u.zoom_params.x);
  let scale = mix(1.6, 6.8, u.zoom_params.y);
  let intensity = u.zoom_params.z;
  let colorShift = u.zoom_params.w;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let audioEnergy = dot(vec3<f32>(bass, mids, treble), vec3<f32>(0.45, 0.35, 0.20));

  let mouseDelta = (uv - u.zoom_config.yz) * aspectVec;
  let mouseRadius = length(mouseDelta);
  let mouseDir = mouseDelta / max(mouseRadius, 0.001);
  let mouseTangent = vec2<f32>(-mouseDir.y, mouseDir.x);
  let held = select(0.35, 1.0, u.zoom_config.w > 0.5);
  let lens = exp(-mouseRadius * mouseRadius * 9.0) * held;

  var clickWave = 0.0;
  var clickCurl = vec2<f32>(0.0);
  let rippleCount = min(u32(u.config.y), 50u);
  for (var ri = 0u; ri < rippleCount; ri += 1u) {
    let ripple = u.ripples[ri];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 2.4) {
      let delta = (uv - ripple.xy) * aspectVec;
      let radius = length(delta);
      let front = smoothstep(0.035, 0.0, abs(radius - age * (0.24 + speed * 0.16))) * exp(-age * 0.9);
      let direction = delta / max(radius, 0.001);
      clickWave += front;
      clickCurl += vec2<f32>(-direction.y, direction.x) * front * select(-1.0, 1.0, (ri % 2u) == 0u);
    }
  }

  let flowTime = time * speed * (1.0 + bass * 0.28);
  var p = centered * scale;
  p += mouseTangent * lens * (0.5 + u.zoom_params.y * 0.8);
  p += clickCurl * 0.55;

  let q = vec2<f32>(
    fbm(p + vec2<f32>(flowTime * 0.9, -flowTime * 0.25)),
    fbm(p + vec2<f32>(5.2 - flowTime * 0.35, 1.3 + flowTime * 0.7))
  );
  let r = vec2<f32>(
    fbm(p + q * (2.5 + bass) + vec2<f32>(1.7, 9.2) + flowTime * 0.45),
    fbm(p + q.yx * (3.0 + mids) + vec2<f32>(8.3, 2.8) - flowTime * 0.38)
  );
  let curl = curlField(p * 0.72 + r * 2.0, flowTime);
  let field = fbm(p + r * 3.8 + curl * 0.32);

  // Phase-related ridges read as braided plasma rather than undifferentiated FBM.
  let phase = dot(p, normalize(vec2<f32>(0.73, 0.41))) + (q.x - q.y) * 5.0;
  let braidA = pow(abs(sin(phase * 1.7 - flowTime * 3.1)), 9.0);
  let braidB = pow(abs(sin(phase * 2.35 + r.x * 5.0 + flowTime * 2.2)), 13.0);
  let filament = (braidA * 0.7 + braidB * 0.45) * smoothstep(0.28, 0.82, field);
  let knots = pow(max(0.0, 1.0 - abs(q.x - r.y) * 5.5), 7.0) * smoothstep(0.48, 0.9, field);
  let density = clamp(field * field * 0.75 + filament + knots * 0.65 + clickWave * 0.5, 0.0, 2.5);

  // Depth gradients bend the flow around existing scene geometry.
  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  let dL = textureLoad(readDepthTexture, clampPixel(pixel + vec2<i32>(-1, 0), dims), 0).r;
  let dR = textureLoad(readDepthTexture, clampPixel(pixel + vec2<i32>(1, 0), dims), 0).r;
  let dD = textureLoad(readDepthTexture, clampPixel(pixel + vec2<i32>(0, -1), dims), 0).r;
  let dU = textureLoad(readDepthTexture, clampPixel(pixel + vec2<i32>(0, 1), dims), 0).r;
  let depthCurl = vec2<f32>(dU - dD, dL - dR);

  let sourceOffset = (curl * (0.003 + intensity * 0.009) + depthCurl * 0.025 + clickCurl * 0.004) / aspectVec;
  let red = textureSampleLevel(readTexture, u_sampler, clamp(uv + sourceOffset * (1.0 + treble * 0.35), vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).r;
  let green = textureSampleLevel(readTexture, u_sampler, clamp(uv + sourceOffset * 0.25, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).g;
  let blue = textureSampleLevel(readTexture, u_sampler, clamp(uv - sourceOffset * (0.8 + bass * 0.25), vec2<f32>(0.001), vec2<f32>(0.999)), 0.0).b;
  let source = vec3<f32>(red, green, blue);

  let palette = max(cosinePalette(field + q.x * 0.35 + audioEnergy * 0.12, colorShift), vec3<f32>(0.0));
  let core = vec3<f32>(1.25, 1.05, 0.78) * (filament * 0.65 + knots * 1.2 + clickWave * 0.45);
  let nebula = palette * density * (0.55 + intensity * 1.75) * (0.75 + audioEnergy * 0.5);
  let starCell = floor((centered + curl * 0.025) * (86.0 + scale * 5.0));
  let starSeed = hash21(starCell);
  let star = pow(max(0.0, sin(time * (1.2 + starSeed * 2.0) + starSeed * TAU)), 18.0)
    * step(0.972 - treble * 0.012, starSeed) * (0.5 + filament);
  var live = source * (0.78 - density * 0.10) + nebula + core + vec3<f32>(0.7, 0.85, 1.2) * star;

  // Exact C history, advected by the current curl. A remains authoritative.
  let historyOffset = vec2<i32>(round((curl * 1.4 + mouseTangent * lens * 1.2 + clickCurl) * (1.0 + speed * 2.0)));
  let prev = textureLoad(dataTextureC, clampPixel(pixel - historyOffset, dims), 0);
  let historyWeight = clamp(0.72 + (1.0 - speed) * 0.12, 0.0, 0.88);
  let temporal = mix(live, prev.rgb * 0.965, historyWeight * smoothstep(0.03, 0.38, density));
  live = max(temporal, live * 0.72);

  let alphaLive = clamp(density * 0.48 + filament * 0.35 + knots * 0.3 + star * 0.2, 0.0, 1.0);
  let alpha = mix(alphaLive, prev.a * 0.95, historyWeight * 0.45);
  textureStore(dataTextureA, pixel, vec4<f32>(min(live, vec3<f32>(8.0)), alpha));
  textureStore(writeTexture, pixel, vec4<f32>(acesToneMap(live), alpha));

  let generatedDepth = clamp(density * 0.28 + knots * 0.25 + lens * 0.08, 0.0, 0.82);
  textureStore(writeDepthTexture, pixel, vec4<f32>(max(depth * 0.82, generatedDepth), 0.0, 0.0, 0.0));
}
