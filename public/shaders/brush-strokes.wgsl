// ═══════════════════════════════════════════════════════════════════
//  Brush Strokes
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba, fast-motion
//  Complexity: High
//  Upgraded: 2026-09-06
//  A packing: ACES display RGBA
//  Motion: spring bristle stroke advection + wet paint ripple spatters
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
  zoom_params: vec4<f32>,  // x=BrushSize, y=TextureAmount, z=ColorIntensity, w=Speed
  ripples: array<vec4<f32>, 50>,
};

fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y
  );
}

fn fbm(p0: vec2<f32>) -> f32 {
  var p = p0;
  var a = 0.5;
  var s = 0.0;
  for (var i = 0; i < 4; i = i + 1) {
    s += noise2(p) * a;
    p = p * 2.08 + vec2<f32>(13.7, 5.9);
    a *= 0.5;
  }
  return s;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) {
    return;
  }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / dims;
  let aspect = dims.x / max(dims.y, 1.0);
  let aspectVec = vec2<f32>(aspect, 1.0);
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let held = u.zoom_config.w > 0.5;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let binA = plasmaBuffer[1].z;
  let binB = plasmaBuffer[5].x;

  // Single-writer spring cursor in extraBuffer[133..138]
  var spring = mouse;
  let hasSpring = arrayLength(&extraBuffer) > 138u;
  if (hasSpring && extraBuffer[138] > 0.5) {
    spring = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  }
  if (gid.x == 0u && gid.y == 0u && hasSpring) {
    var pos = spring;
    var vel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[138] <= 0.5) {
      pos = mouse;
      vel = vec2<f32>(0.0);
    } else {
      let dt = clamp(time - extraBuffer[137], 0.001, 0.05);
      let omega = 14.0;
      vel += ((mouse - pos) * (omega * omega) - vel * (2.0 * omega)) * dt;
      vel = clamp(vel, vec2<f32>(-4.0), vec2<f32>(4.0));
      pos += vel * dt;
    }
    extraBuffer[133] = pos.x;
    extraBuffer[134] = pos.y;
    extraBuffer[135] = vel.x;
    extraBuffer[136] = vel.y;
    extraBuffer[137] = time;
    extraBuffer[138] = 1.0;
    spring = pos;
  }

  // Four saved controls preserved
  let brushRadius = mix(0.04, 0.45, u.zoom_params.x) * (1.0 + bass * 0.25);
  let textureAmount = u.zoom_params.y;
  let colorIntensity = u.zoom_params.z;
  let strokeSpeed = mix(0.2, 2.5, u.zoom_params.w);

  // Depth sampling
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthFade = mix(0.7, 1.3, depth);

  // Capped click ripple paint spatters
  var spatterEnergy = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let age = time - r.z;
    if (age > 0.0 && age < 2.2) {
      let d = length((uv - r.xy) * aspectVec);
      let ring = exp(-abs(d - age * 0.45) * 30.0) * exp(-age * 1.5);
      // Organic droplet spatter around ring
      let dropNoise = hash21(floor(uv * 120.0));
      let drops = smoothstep(0.7, 0.95, dropNoise) * ring;
      spatterEnergy += ring * 0.7 + drops * 1.5;
    }
  }

  // Spring cursor proximity & velocity
  let toSpring = (uv - spring) * aspectVec;
  let dist = length(toSpring);
  let strokeActive = smoothstep(brushRadius, brushRadius * 0.15, dist) * select(1.0, 1.7, held);

  // Bristle friction field
  let strokeAngle = atan2(toSpring.y, toSpring.x);
  let bristleCoord = uv * vec2<f32>(45.0, 140.0) + vec2<f32>(time * 0.15 * strokeSpeed, -time * 0.08 * strokeSpeed);
  let bristleNoise = fbm(bristleCoord);
  let strokeFlow = sin(strokeAngle * 4.0 + time * strokeSpeed * 3.0 + bristleNoise * 3.5) * 0.5 + 0.5;

  let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

  // Glaze palette cycling
  let hue = fract(time * 0.06 + colorIntensity * 0.35 + mids * 0.25);
  let glazePalette = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.094, 4.188) + hue * 6.28318);
  let warmGlaze = mix(glazePalette, vec3<f32>(1.0, 0.75, 0.45), bass * 0.4);

  // Impasto layer formulation
  let brushMask = clamp(strokeActive * (0.35 + strokeFlow * 0.65) * (0.8 + bass * 0.4) + spatterEnergy * 0.6, 0.0, 1.0);
  let impastoRelief = pow(brushMask, 2.0) * (0.3 + bristleNoise * 0.7 * textureAmount);
  let wetBorder = smoothstep(brushRadius * 0.9, brushRadius * 0.5, dist) * smoothstep(brushRadius * 0.1, brushRadius * 0.5, dist);

  let glazedColor = mix(baseColor, baseColor * warmGlaze * 1.45, colorIntensity * 0.55);
  var hdr = mix(baseColor, glazedColor, brushMask);
  hdr += glazePalette * impastoRelief * (0.5 + mids * 0.6);
  hdr += vec3<f32>(1.0, 0.9, 0.7) * wetBorder * (0.2 + treble * 0.6 + binA * 0.3);

  // Canvas grain relief
  let canvasGrain = (noise2(uv * 400.0) - 0.5) * 0.06 * textureAmount * (1.0 + treble * 0.4);
  hdr += vec3<f32>(canvasGrain);

  // Exact previous frame history load from dataTextureC for persistent paint accumulation
  let hist = textureLoad(dataTextureC, coord, 0);
  let paintPersistence = mix(0.06, 0.30, brushMask);
  hdr = mix(hdr, hist.rgb, paintPersistence);

  let finalRGB = acesToneMap(hdr);
  let luma = dot(finalRGB, vec3<f32>(0.2126, 0.7152, 0.0722));
  let semanticAlpha = clamp(0.75 + brushMask * 0.2 + wetBorder * 0.2 + spatterEnergy * 0.3, 0.0, 1.0);
  let outCol = vec4<f32>(finalRGB, semanticAlpha);

  textureStore(writeTexture, coord, outCol);
  textureStore(dataTextureA, coord, outCol);
  textureStore(writeDepthTexture, coord, vec4<f32>(clamp(mix(depth, depth * depthFade + impastoRelief * 0.4, 0.35), 0.0, 1.0), 0.0, 0.0, 0.0));
}
