// ═══════════════════════════════════════════════════════════════════
//  hyper-chromatic-delay - Spectral Multi-Tap Echo
//  Category: image
//  Features: upgraded-rgba, depth-aware, spectral-dispersion, multi-tap-temporal, lens-distortion, motion-trails, audio-reverb
//  Complexity: Very High
//  Upgraded by: Visualist Agent
//  Date: 2026-05-03
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
  config: vec4<f32>,              // x=time, y=frame/mouseMode, z=resX, w=resY
  zoom_config: vec4<f32>,         // x=time, y=mouseX, z=mouseY, w=mouseDown
  zoom_params: vec4<f32>,         // User params 1-4
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
  if (lambda < 440.0) { return vec3<f32>(-(lambda - 440.0) / 60.0, 0.0, 1.0); }
  else if (lambda < 490.0) { return vec3<f32>(0.0, (lambda - 440.0) / 50.0, 1.0); }
  else if (lambda < 510.0) { return vec3<f32>(0.0, 1.0, -(lambda - 510.0) / 20.0); }
  else if (lambda < 580.0) { return vec3<f32>((lambda - 510.0) / 70.0, 1.0, 0.0); }
  else if (lambda < 645.0) { return vec3<f32>(1.0, -(lambda - 645.0) / 65.0, 0.0); }
  else { return vec3<f32>(1.0, 0.0, 0.0); }
}

fn lensDistort(uv: vec2<f32>, strength: f32) -> vec2<f32> {
  let centered = uv - 0.5;
  let r2 = dot(centered, centered);
  let r4 = r2 * r2;
  let factor = 1.0 + strength * r2 + strength * 0.5 * r4;
  return centered * factor + 0.5;
}

fn sampleSpectral(uv: vec2<f32>, dispersion: f32, direction: vec2<f32>) -> vec3<f32> {
  var col = vec3<f32>(0.0);
  let baseLambda = 650.0;
  let stepSize = dispersion / 6.0;
  for (var i: i32 = 0; i < 7; i = i + 1) {
    let l = baseLambda - f32(i) * stepSize;
    let shift = direction * (l - 550.0) * 0.00002;
    let s = textureSampleLevel(readTexture, u_sampler, uv + shift, 0.0).rgb;
    col = col + s * wavelengthToRGB(l);
  }
  return col / 7.0;
}

fn rgbToLuma(rgb: vec3<f32>) -> f32 {
  return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn ACESFilm(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x*(a*x+b))/(x*(c*x+d)+e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let coord = vec2<i32>(global_id.xy);
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  
  // Audio reactivity
  let bass = plasmaBuffer[0].x;
  let mid = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Single-writer spring
  let is_leader = (global_id.x == 0u && global_id.y == 0u);
  if (is_leader) {
      let dt = 0.016;
      let target = u.zoom_config.w; // mouseDown
      let k = 100.0;
      let d = 10.0;
      let current = extraBuffer[133];
      let vel = extraBuffer[134];
      let force = k * (target - current) - d * vel;
      let new_vel = vel + force * dt;
      var new_val = current + new_vel * dt;
      new_val = clamp(new_val, 0.0, 1.0);
      extraBuffer[133] = new_val;
      extraBuffer[134] = new_vel;
  }
  
  workgroupBarrier();
  let spring_val = extraBuffer[133];
  
  var ripple_acc = 0.0;
  for(var i=0u; i<10u; i++) {
      let r = u.ripples[i];
      if (r.w > 0.0) {
          let aspect = resolution.x / resolution.y;
          let r_uv = vec2<f32>(r.x, r.y);
          let dist = distance(vec2<f32>(uv.x * aspect, uv.y), vec2<f32>(r_uv.x * aspect, r_uv.y));
          let time_diff = time - r.z;
          let r_width = 0.05 + 0.1 * spring_val;
          let r_dist = dist - time_diff * 0.5;
          let intensity = exp(-time_diff * 2.0) * smoothstep(r_width, 0.0, abs(r_dist));
          ripple_acc += intensity * min(1.0, 1.0 / (time_diff * 10.0 + 1.0)); // capped
      }
  }
  
  let pointer_held_effect = spring_val * max(0.0, 1.0 - distance(uv, u.zoom_config.yz) * 3.0);
  let geometry_base = vec2<f32>(sin(uv.x * 20.0 + time) * cos(uv.y * 20.0 - time * 0.5) * 0.1, cos(uv.x * 20.0 - time) * sin(uv.y * 20.0 + time * 0.5) * 0.1);

  let separation_strength = u.zoom_params.x * 0.1;
  let trail_decay = mix(0.5, 0.99, u.zoom_params.y);
  let hue_shift_speed = u.zoom_params.z;
  let mouse_influence = u.zoom_params.w;

  let mousePos = u.zoom_config.yz;
  let aspect = resolution.x / resolution.y;
  let uv_corrected = vec2<f32>(uv.x * aspect, uv.y);
  let mouse_corrected = vec2<f32>(mousePos.x * aspect, mousePos.y);
  let dist = distance(uv_corrected, mouse_corrected);
  let influence = smoothstep(0.5, 0.0, dist) * mouse_influence + pointer_held_effect * 0.5;

  let prevFrame = textureLoad(dataTextureC, coord, 0).rgb;

  let motionDir = normalize(mouse_corrected - uv_corrected + vec2<f32>(0.001, 0.001));
  let motionMag = length(mouse_corrected - uv_corrected);

  var temporalAccum = vec3<f32>(0.0);
  let taps = 5;
  var totalWeight = 0.0;
  for(var t: i32 = 0; t < taps; t = t + 1) {
    let fi = f32(t);
    let tapUV = uv + motionDir * fi * 0.003 * motionMag * mouse_influence + geometry_base * 0.1;
    let tapWeight = exp(-fi * 0.7);
    temporalAccum = temporalAccum + textureSampleLevel(readTexture, u_sampler, tapUV, 0.0).rgb * tapWeight;
    totalWeight = totalWeight + tapWeight;
  }
  temporalAccum = temporalAccum / max(totalWeight, 0.001);

  let lensStrengthR = mix(-0.3, 0.3, u.zoom_params.x) * 1.2 + ripple_acc * 0.1;
  let lensStrengthG = mix(-0.3, 0.3, u.zoom_params.x) + ripple_acc * 0.05;
  let lensStrengthB = mix(-0.3, 0.3, u.zoom_params.x) * 0.8 - ripple_acc * 0.05;
  let lensUVR = lensDistort(uv, lensStrengthR + influence * 0.1);
  let lensUVG = lensDistort(uv, lensStrengthG);
  let lensUVB = lensDistort(uv, lensStrengthB - influence * 0.1);

  let dispersion = mix(0.0, 300.0, separation_strength + influence * 0.1) * (1.0 + treble * 2.0);
  let angle = time * hue_shift_speed + dist * 10.0;
  let dir = vec2<f32>(cos(angle), sin(angle));

  let spectralR = sampleSpectral(lensUVR, dispersion, dir).r;
  let spectralG = sampleSpectral(lensUVG, dispersion, dir).g;
  let spectralB = sampleSpectral(lensUVB, dispersion, dir).b;
  var spectralColor = vec3<f32>(spectralR, spectralG, spectralB);

  let reverb = bass * 0.4 + mid * 0.2;
  let echoCount = 4;
  var echoColor = vec3<f32>(0.0);
  var echoWeight = 0.0;
  for(var e: i32 = 0; e < echoCount; e = e + 1) {
    let fi = f32(e) + 1.0;
    let echoUV = uv + dir * fi * 0.012 * (1.0 + reverb * 2.0);
    let echoSample = textureSampleLevel(readTexture, u_sampler, echoUV, 0.0).rgb;
    let w = 1.0 / (fi * fi);
    echoColor = echoColor + echoSample * w;
    echoWeight = echoWeight + w;
  }
  echoColor = echoColor / max(echoWeight, 0.001);

  var color = mix(spectralColor, temporalAccum, 0.25);
  color = mix(color, echoColor, 0.15 + reverb * 0.35);
  color = mix(color, prevFrame, trail_decay * 0.45);

  let luma = rgbToLuma(color);
  let contrast = 1.0 + u.zoom_params.x * 0.5;
  color = (color - vec3<f32>(0.5)) * contrast + vec3<f32>(0.5);
  color = color + vec3<f32>(0.02 * sin(luma * 10.0 + time));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  color = mix(color, color * (1.0 + depth * 0.4), 0.35);

  color = ACESFilm(color);
  
  let sem_alpha = clamp(luma + ripple_acc + pointer_held_effect, 0.0, 1.0);

  let final_color = vec4<f32>(color, sem_alpha);
  
  textureStore(writeTexture, coord, final_color);
  textureStore(dataTextureA, coord, final_color);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
