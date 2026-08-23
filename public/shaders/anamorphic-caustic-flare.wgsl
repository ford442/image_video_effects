// ═══════════════════════════════════════════════════════════════════
//  Anamorphic Caustic Flare — Cinematic Lens & Living Water Caustics
//  Category: visual-effects
//  Features: anamorphic, caustic, lens-flare, refraction, audio-stretch,
//            mouse-tilt, cinematic, semantic-alpha, ACES
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
  config: vec4<f32>,       // [time, rippleCount, resW, resH]
  zoom_config: vec4<f32>,  // [time, mouseX, mouseY, mouseDown]
  zoom_params: vec4<f32>,  // x=Flare, y=Caustic, z=Refraction, w=Stretch
  ripples: array<vec4<f32>, 50>,
};

fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

fn caustic(p: vec2<f32>, t: f32, freq: f32) -> f32 {
  let q = p * freq + vec2<f32>(t * 0.6, t * -0.4);
  let c1 = sin(q.x * 1.7 + sin(q.y * 2.3)) * 0.5 + 0.5;
  let c2 = sin(q.y * 2.1 + sin(q.x * 1.4 + t * 0.8)) * 0.5 + 0.5;
  return pow(c1 * c2, 1.6);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

  let pixel = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / res;
  let aspect = res.x / max(res.y, 1.0);
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Sliders: exact parameter contracts
  let flareParam = u.zoom_params.x;      // 0..1.6, default 0.7
  let causticParam = u.zoom_params.y;    // 0..1.8, default 0.85
  let refractParam = u.zoom_params.z;    // 0..1.0, default 0.6
  let stretchParam = u.zoom_params.w;    // 0..1.0, default 0.5

  let flareStrength = flareParam * (0.75 + bass * 0.85);
  let causticStrength = causticParam * (0.8 + treble * 0.7);
  let refraction = refractParam * 0.04;
  let stretch = stretchParam * (1.0 + bass * 0.75);

  let rawMouse = u.zoom_config.yz;
  let held = select(0.0, 1.0, u.zoom_config.w > 0.5);

  // Critically-damped lens tilt spring in extraBuffer[133..138]
  let isWriter = (global_id.x == 0u && global_id.y == 0u);
  let hasState = (arrayLength(&extraBuffer) > 138u);
  var sprungMouse = rawMouse;
  if (hasState && extraBuffer[138] > 0.5) {
    sprungMouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  }

  if (isWriter && hasState) {
    let lastTime = extraBuffer[137];
    let dt = clamp(time - lastTime, 0.0, 0.1);
    var sPos = sprungMouse;
    var sVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[138] < 0.5) {
      sPos = rawMouse;
      sVel = vec2<f32>(0.0);
    }
    let omega = 8.0;
    let accel = omega * omega * (rawMouse - sPos) - 2.0 * omega * sVel;
    sVel += accel * dt;
    sPos += sVel * dt;
    extraBuffer[133] = sPos.x;
    extraBuffer[134] = sPos.y;
    extraBuffer[135] = sVel.x;
    extraBuffer[136] = sVel.y;
    extraBuffer[137] = time;
    extraBuffer[138] = 1.0;
  }

  let mouseTilt = (sprungMouse.x - 0.5) * 0.5;
  let flareY = mix(0.5, sprungMouse.y, 0.35);

  // Anamorphic horizontal flare (classic cinematic cyan + cobalt + amber)
  let centerDist = abs(uv.y - flareY) * 1.8;
  let anamorph = smoothstep(0.09, 0.0, centerDist) * flareStrength;
  let flareCol = mix(vec3<f32>(0.2, 0.6, 1.0), vec3<f32>(1.0, 0.65, 0.2), uv.x * 0.6 + 0.2);
  var flare = flareCol * pow(anamorph, 1.25) * (1.0 + bass * 0.5);

  // Horizontal streak core
  let streak = smoothstep(0.012, 0.0, abs(uv.y - flareY)) * (0.65 + bass * 0.45);
  flare += vec3<f32>(0.85, 0.92, 1.0) * streak * (flareStrength * 0.8);

  // Click flare bursts
  var burstFlash = 0.0;
  var burstEnergy = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age < 0.0 || age > 1.6) { continue; }
    burstFlash = max(burstFlash, exp(-age * 2.2) * smoothstep(0.025, 0.0, abs(uv.y - ripple.y)));
    let clickDist = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
    burstEnergy = max(burstEnergy, exp(-age * 3.0) * smoothstep(0.28, 0.0, clickDist));
  }
  flare += vec3<f32>(0.9, 0.95, 1.0) * burstFlash * (flareStrength * 1.2);

  // Living water caustics that refract the image
  let c = caustic(uv + vec2<f32>(mouseTilt * 0.1, 0.0), time * 0.75 + mids * 0.35, 8.0 + stretch * 5.0);
  var causticMask = pow(c, 2.0) * causticStrength;

  // Regional FFT modulation
  let band = min(u32(uv.x * 7.0), 7u);
  causticMask *= (1.0 + plasmaBuffer[(band % 8u) + 1u].x * 0.35);
  causticMask = min(causticMask + burstEnergy * causticStrength * 0.8, 3.0);

  // Refraction vector based on caustic gradient
  let refractUV = clamp(
    uv + vec2<f32>(causticMask * refraction * (sprungMouse.x - 0.5) * 2.0, causticMask * refraction * 0.7),
    vec2<f32>(0.0),
    vec2<f32>(1.0)
  );

  let input = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let refracted = textureSampleLevel(readTexture, u_sampler, refractUV, 0.0);

  // Chromatic aberration on flare highlights
  let caOff = flareStrength * 0.002;
  let rSample = textureSampleLevel(readTexture, u_sampler, clamp(refractUV + vec2<f32>(caOff, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let bSample = textureSampleLevel(readTexture, u_sampler, clamp(refractUV - vec2<f32>(caOff * 0.8, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  let chromaRefract = vec3<f32>(rSample, refracted.g, bSample);

  // Blend refracted image with caustic highlights
  let causticLight = vec3<f32>(0.65, 0.88, 1.0) * (causticMask * 1.6);
  var col = mix(input.rgb, chromaRefract, clamp(0.35 + causticMask * 0.55, 0.0, 1.0));
  col += causticLight * (0.4 + mids * 0.35);

  // Anamorphic flare composite
  col = col * (1.0 - flareStrength * 0.2) + flare * 0.9;

  // Exact dataTextureC temporal light persistence
  let prev = textureLoad(dataTextureC, pixel, 0).rgb;
  col = mix(col, prev, 0.1 + held * 0.08);

  // ACES Tonemap
  let finalRGB = aces(col);

  // Semantic alpha: energetic flare + caustic brightness + source alpha
  let energy = causticMask * 0.6 + anamorph * 0.85 + streak * 0.5;
  let semanticAlpha = clamp(mix(input.a, 0.65 + energy * 0.45, 0.8) + burstFlash * 0.15, 0.4, 1.0);

  let depth = clamp(0.2 + causticMask * 0.5 + anamorph * 0.3, 0.0, 0.98);
  let finalPixel = vec4<f32>(finalRGB, semanticAlpha);

  textureStore(writeTexture, pixel, finalPixel);
  textureStore(dataTextureA, pixel, finalPixel);
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
