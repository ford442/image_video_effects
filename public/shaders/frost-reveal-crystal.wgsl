// ═══════════════════════════════════════════════════════════════════
//  frost-reveal-crystal — Anisotropic Dendritic Frost & Crystal Growth
//  Category: advanced-hybrid
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba,
//            frost-reveal, crystal-growth, semantic-alpha, ACES
//  Complexity: Very High
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
  zoom_params: vec4<f32>,  // x=GrowthSpeed, y=MeltRadius, z=MaxOpacity, w=Anisotropy
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u2 = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash12(i + vec2<f32>(0.0, 0.0)), hash12(i + vec2<f32>(1.0, 0.0)), u2.x),
    mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0, 1.0)), u2.x),
    u2.y
  );
}

fn fbm(p: vec2<f32>) -> f32 {
  var v = 0.0;
  var a = 0.5;
  let rot = mat2x2<f32>(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
  var pos = p;
  for (var i = 0; i < 4; i = i + 1) {
    v += a * noise(pos);
    pos = rot * pos * 2.0 + vec2<f32>(100.0);
    a *= 0.5;
  }
  return v;
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(global_id.xy);
  let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let rawMouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w > 0.5;
  let held = select(0.0, 1.0, mouseDown);

  // Critically damped spring cursor in extraBuffer[133..138]
  let isWriter = (global_id.x == 0u && global_id.y == 0u);
  let hasState = (arrayLength(&extraBuffer) > 138u);

  var mouse = rawMouse;
  if (hasState && extraBuffer[138] > 0.5) {
    mouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  }

  if (isWriter && hasState) {
    let lastTime = extraBuffer[137];
    let dt = clamp(time - lastTime, 0.0, 0.05);
    var sPos = mouse;
    var sVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[138] < 0.5) {
      sPos = rawMouse;
      sVel = vec2<f32>(0.0);
    }
    let stiffness = 42.0;
    let damping = 12.96; // 2 * sqrt(42)
    let accel = (rawMouse - sPos) * stiffness - sVel * damping;
    sVel += accel * dt;
    sPos += sVel * dt;
    extraBuffer[133] = sPos.x;
    extraBuffer[134] = sPos.y;
    extraBuffer[135] = sVel.x;
    extraBuffer[136] = sVel.y;
    extraBuffer[137] = time;
    extraBuffer[138] = 1.0;
  }

  // Exact parameter contracts
  let growth_speed = u.zoom_params.x * 0.06 * (1.0 + bass * 0.4);
  let melt_radius = u.zoom_params.y * 0.35 + 0.02;
  let max_opacity = u.zoom_params.z;
  let anisotropy = mix(0.0, 0.6, u.zoom_params.w);

  let dist_vec = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let dist = length(dist_vec);

  // Exact load from dataTextureC
  let prev = textureLoad(dataTextureC, coord, 0);
  var mask = prev.r;
  var phase = prev.g;
  var orientation = prev.b;
  var impurity = prev.a;

  if (time < 0.1) {
    mask = 0.5;
    phase = 0.0;
    orientation = 0.0;
    impurity = hash12(uv * 100.0) * 0.1;
    if (length(uv - vec2<f32>(0.5)) < 0.03) {
      phase = 1.0;
      orientation = atan2(uv.y - 0.5, uv.x - 0.5);
    }
  }

  // Melt frost near mouse
  let melt = smoothstep(melt_radius, melt_radius * 0.4, dist) * (0.8 + held * 0.2);
  mask = mix(mask, 0.0, melt * 0.3);
  mask += growth_speed * (1.0 - mask * 0.5);
  mask = clamp(mask, 0.0, 1.0);

  // Anisotropic crystal phase field using exact loads of 4-neighborhood
  let iMax = vec2<i32>(i32(resolution.x) - 1, i32(resolution.y) - 1);
  let left = textureLoad(dataTextureC, clamp(coord - vec2<i32>(1, 0), vec2<i32>(0), iMax), 0);
  let right = textureLoad(dataTextureC, clamp(coord + vec2<i32>(1, 0), vec2<i32>(0), iMax), 0);
  let down = textureLoad(dataTextureC, clamp(coord - vec2<i32>(0, 1), vec2<i32>(0), iMax), 0);
  let up = textureLoad(dataTextureC, clamp(coord + vec2<i32>(0, 1), vec2<i32>(0), iMax), 0);

  let lapPhase = left.g + right.g + down.g + up.g - 4.0 * phase;
  let gradPhase = vec2<f32>(right.g - left.g, up.g - down.g) * 0.5;
  let dir = vec2<f32>(cos(orientation), sin(orientation));
  let alignment = abs(dot(normalize(gradPhase + vec2<f32>(0.0001)), dir));
  let anisoFactor = 1.0 + anisotropy * (alignment - 0.5) * 2.0;

  let supercooling = 0.5 + mids * 0.2;
  let m = supercooling * (1.0 - 2.0 * impurity);
  let phaseReaction = phase * (1.0 - phase) * (phase - 0.5 + m * 0.5);
  let growthRate = mix(0.002, 0.012, u.zoom_params.x);
  phase += phaseReaction * growthRate * anisoFactor + lapPhase * 0.1 * growthRate;
  phase = clamp(phase, 0.0, 1.0);

  // Mouse seeds crystals
  let mouseInfluence = smoothstep(0.05, 0.0, dist) * held;
  phase = mix(phase, 1.0, mouseInfluence);
  if (mouseInfluence > 0.01) {
    orientation = atan2(uv.y - mouse.y, uv.x - mouse.x);
  }

  // Click ripples melt & shock-freeze
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let age = time - r.z;
    if (age >= 0.0 && age < 2.0) {
      let rDist = length((uv - r.xy) * vec2<f32>(aspect, 1.0));
      let wave = exp(-abs(rDist - age * 0.5) * 15.0) * (1.0 - age * 0.5);
      mask = mix(mask, 0.0, wave * 0.6);
      phase = mix(phase, 1.0, wave * 0.4);
    }
  }

  // Frost visuals
  let frost_pattern = fbm(uv * 10.0 + time * 0.05);
  let frost_detail = fbm(uv * 20.0 - time * 0.03);
  let combined_frost = smoothstep(0.3, 0.7, frost_pattern * 0.6 + frost_detail * 0.4);
  let offset = (vec2<f32>(frost_pattern, frost_detail) - 0.5) * 0.05 * mask;
  let distorted_uv = clamp(uv + offset, vec2<f32>(0.001), vec2<f32>(0.999));

  let orientNorm = fract(orientation / 6.2831853);
  let h6 = orientNorm * 6.0;
  let c = 0.8;
  let x = c * (1.0 - abs(h6 - floor(h6 / 2.0) * 2.0 - 1.0));
  var crystalColor = vec3<f32>(c, x, 0.3);
  if (h6 >= 1.0 && h6 < 2.0) { crystalColor = vec3<f32>(x, c, 0.3); }
  else if (h6 >= 2.0 && h6 < 3.0) { crystalColor = vec3<f32>(0.3, c, x); }
  else if (h6 >= 3.0 && h6 < 4.0) { crystalColor = vec3<f32>(0.3, x, c); }
  else if (h6 >= 4.0 && h6 < 5.0) { crystalColor = vec3<f32>(x, 0.3, c); }
  else if (h6 >= 5.0) { crystalColor = vec3<f32>(c, 0.3, x); }

  let interfaceMask = smoothstep(0.3, 0.5, phase) * smoothstep(0.7, 0.5, phase);
  var displayColor = mix(vec3<f32>(0.05, 0.08, 0.15), crystalColor, smoothstep(0.4, 0.6, phase));
  displayColor = mix(displayColor, vec3<f32>(0.9, 0.95, 1.0), interfaceMask * 0.5 + treble * 0.2);

  let clear_color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let frost_color_sample = textureSampleLevel(readTexture, u_sampler, distorted_uv, 0.0).rgb;
  let frosted_look = mix(frost_color_sample, vec3<f32>(0.9, 0.95, 1.0), 0.45 * mask * max_opacity);

  let visibility = mask * combined_frost * max_opacity;
  let crystalVisibility = smoothstep(0.4, 0.6, phase) * (1.0 - mask);
  var finalRGB = mix(clear_color, frosted_look, visibility);
  finalRGB = mix(finalRGB, displayColor, crystalVisibility * 0.85);

  finalRGB = aces(finalRGB);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let alpha = clamp(0.3 + visibility * 0.5 + crystalVisibility * 0.4 + held * 0.1, 0.15, 1.0);
  let finalPixel = vec4<f32>(finalRGB, alpha);

  textureStore(writeTexture, coord, finalPixel);
  textureStore(dataTextureA, coord, vec4<f32>(mask, phase, orientation, impurity));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
