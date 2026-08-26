// ═══════════════════════════════════════════════════════════════════
//  Glass Brick Wall — Textured Architectural Glass Surface
//  Category: distortion
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba,
//            caustic-refraction, depth-layers, chromatic-dispersion, fbm-texture, ACES
//  Complexity: High
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
  zoom_params: vec4<f32>,  // x=BrickSize, y=Distortion, z=MortarSize, w=GlassDensity
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
  let h = sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453;
  return fract(h);
}

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash12(i + vec2<f32>(0.0, 0.0)), hash12(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y
  );
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var total = 0.0;
  var amplitude = 0.5;
  var frequency = 1.0;
  for (var i = 0; i < octaves; i = i + 1) {
    total += amplitude * noise2(p * frequency);
    amplitude *= 0.5;
    frequency *= 2.1;
  }
  return total;
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

  let pixel = vec2<i32>(gid.xy);
  let uv = vec2<f32>(gid.xy) / dims;
  let aspect = dims.x / max(dims.y, 1.0);
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let rawMouse = u.zoom_config.yz;
  let held = select(0.0, 1.0, u.zoom_config.w > 0.5);

  // Critically damped spring cursor in extraBuffer[133..138]
  let isWriter = (gid.x == 0u && gid.y == 0u);
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
  let brickSize = mix(10.0, 54.0, u.zoom_params.x);
  let distortion = mix(0.0, 0.12, u.zoom_params.y);
  let mortarSize = mix(0.01, 0.12, u.zoom_params.z);
  let glassDensity = mix(0.6, 2.6, u.zoom_params.w);

  let gridUV = uv * vec2<f32>(brickSize * aspect, brickSize);
  let cellId = floor(gridUV);
  let cell = fract(gridUV) - 0.5;

  // FBM-perturbed normal for organic glass surface
  let normalNoise = fbm(cell * 4.0 + cellId * 0.5 + time * 0.05, 5) * 0.15;
  let normalXY = cell * -2.0 + vec2<f32>(normalNoise, normalNoise * 0.7);
  let normalZ = sqrt(max(0.0, 1.0 - dot(normalXY, normalXY)));
  let normal = normalize(vec3<f32>(normalXY, normalZ));
  let mortarMask = smoothstep(0.48 - mortarSize, 0.5, max(abs(cell.x), abs(cell.y)));

  // Pointer interaction
  let p_dist = length((uv - mouse) * vec2<f32>(aspect, 1.0));
  let ptr_influence = smoothstep(0.35 + held * 0.15, 0.0, p_dist) * (1.0 + bass * 0.5);

  // Click ripple shocks
  let rippleCount = min(u32(u.config.y), 50u);
  var click_wave = 0.0;
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let rAge = time - rp.z;
    if (rAge >= 0.0 && rAge < 2.0) {
      let rDist = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
      let wave = sin((rDist - rAge * 0.5) * 30.0) * exp(-rDist * 3.5) * exp(-rAge * 1.4);
      click_wave += abs(wave) * 0.4;
    }
  }

  let refractOffset = normal.xy * distortion * (1.0 - mortarMask) * (1.0 + bass * 0.35 + ptr_influence * 0.2 + click_wave * 0.5);
  let frontUV = clamp(uv + refractOffset, vec2<f32>(0.0), vec2<f32>(1.0));

  // Chromatic dispersion
  let cr = textureSampleLevel(readTexture, u_sampler, clamp(frontUV + vec2<f32>(0.005) * (treble * 0.5 + 0.5), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let cg = textureSampleLevel(readTexture, u_sampler, frontUV, 0.0).g;
  let cb = textureSampleLevel(readTexture, u_sampler, clamp(frontUV - vec2<f32>(0.005) * (treble * 0.5 + 0.5), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  let base_a = textureSampleLevel(readTexture, u_sampler, frontUV, 0.0).a;

  var color = vec3<f32>(cr, cg, cb);

  // Exact dataTextureC persistence
  let prevC = textureLoad(dataTextureC, pixel, 0).rgb;
  color = mix(color, prevC, 0.07);

  var finalAlpha = base_a;
  if (mortarMask < 0.5) {
    let lightDir = normalize(vec3<f32>(0.0, 0.0, 1.0));
    let spec = pow(max(dot(normal, lightDir), 0.0), 32.0) * (0.5 + mids);
    let glassColor = vec3<f32>(0.85, 0.94, 1.0) * (1.0 - glassDensity * 0.15);
    color = color * glassColor + spec;
    finalAlpha = mix(0.85, 0.3, 1.0 - mortarMask);
  } else {
    color *= 0.3; // mortar is dark
    finalAlpha = 0.95;
  }

  color += ptr_influence * vec3<f32>(0.2, 0.4, 0.8) * mids;
  color += click_wave * vec3<f32>(1.0, 0.85, 0.5);

  let finalRGB = aces(color);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, frontUV, 0.0).r;
  let finalPixel = vec4<f32>(finalRGB, clamp(finalAlpha + ptr_influence * 0.1, 0.1, 1.0));

  textureStore(writeTexture, pixel, finalPixel);
  textureStore(dataTextureA, pixel, finalPixel);
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
