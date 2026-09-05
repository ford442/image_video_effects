// ═══════════════════════════════════════════════════════════════════
//  Bubble Lens — Thin-Film Marangoni Soap Bubble
//  Category: distortion
//  Features: mouse-driven, audio-reactive, upgraded-rgba, thin-film,
//            marangoni-convection, membrane-resonance, ACES
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,  // x=BubbleSize, y=Magnification, z=FilmThickness, w=IOR
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  let a = hash12(i);
  let b = hash12(i + vec2<f32>(1.0, 0.0));
  let c = hash12(i + vec2<f32>(0.0, 1.0));
  let d = hash12(i + vec2<f32>(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn safeNormalize(v: vec2<f32>) -> vec2<f32> {
  let lenSq = max(dot(v, v), 1e-6);
  return v * inverseSqrt(lenSq);
}

fn acesFilm(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

struct BubbleEval {
  color: vec3<f32>,
  inside: f32,
  drainedThickness: f32,
  spec: f32,
  alpha: f32,
  warpedUV: vec2<f32>,
};

fn evalBubble(
  uv: vec2<f32>,
  src: vec4<f32>,
  center: vec2<f32>,
  bubbleRadius: f32,
  magnification: f32,
  filmThickness: f32,
  ior: f32,
  aspect: f32,
  time: f32,
  audio: vec3<f32>,
  broadShimmer: f32,
  fineShimmer: f32,
  filmShock: f32
) -> BubbleEval {
  let delta = (uv - center) * vec2<f32>(aspect, 1.0);
  let dist = length(delta);
  let inside = 1.0 - smoothstep(bubbleRadius, bubbleRadius + 0.02, dist);
  let factor = clamp(dist / max(bubbleRadius, 1e-4), 0.0, 1.0);
  let direction = safeNormalize(delta);

  let lensStrength = (1.0 - factor * factor) * (magnification - 1.0);
  let displacement = direction * lensStrength * bubbleRadius * (1.0 - factor);
  let warpedUV = clamp(uv - displacement / vec2<f32>(aspect, 1.0), vec2<f32>(0.0), vec2<f32>(1.0));

  let bubbleSample = textureSampleLevel(readTexture, u_sampler, warpedUV, 0.0);

  let drainage = clamp(0.5 + delta.y / max(bubbleRadius, 1e-4) * 0.5 + sin(time * 0.45) * 0.04, 0.0, 1.0);
  let turbulence = noise(warpedUV * 8.0 + vec2<f32>(0.0, -time * 0.25)) * 0.6 * (1.0 + broadShimmer)
                 + noise(warpedUV * 15.0 - vec2<f32>(time * 0.1, 0.0)) * 0.4 * (1.0 + fineShimmer);
  var drainedThickness = filmThickness * (0.14 + drainage * 1.6) * (0.75 + turbulence * 0.6);
  drainedThickness = drainedThickness * (1.0 + filmShock);

  // Marangoni convection
  let tangent = vec2<f32>(-direction.y, direction.x);
  let tensionGrad = 1.0 - clamp(drainedThickness * 1.4, 0.0, 1.0);
  let marangoni = dot(tangent, vec2<f32>(cos(time * 0.6), sin(time * 0.47))) * tensionGrad * (0.35 + audio.y * 0.9);
  drainedThickness = drainedThickness * (1.0 + marangoni * 0.28);

  // Per-band membrane resonance drum modes
  var membrane = 0.0;
  for (var m = 0u; m < 8u; m = m + 1u) {
    let fm = f32(m);
    let energy = plasmaBuffer[m + 1u].x;
    let radialMode = cos(factor * (3.0 + fm * 2.4) * 3.14159265);
    let azimuthMode = cos(atan2(delta.y, delta.x) * (fm + 1.0) + time * (1.4 + fm * 0.5));
    membrane += radialMode * azimuthMode * energy / (1.0 + fm * 0.5);
  }
  drainedThickness = max(drainedThickness * (1.0 + membrane * 0.16), 0.0);
  let phase = drainedThickness * 9.0 * (1.0 - factor * 0.45) + audio.z * 2.0;

  var interference = vec3<f32>(
    0.5 + 0.5 * cos(phase),
    0.5 + 0.5 * cos(phase + 2.09),
    0.5 + 0.5 * cos(phase + 4.18)
  );
  let blackSpot = smoothstep(0.12, 0.0, drainedThickness);
  interference = mix(interference, vec3<f32>(0.03, 0.03, 0.04), blackSpot);

  let fresnelBase = pow((ior - 1.0) / (ior + 1.0), 2.0);
  let cosTheta = max(dot(-direction, vec2<f32>(0.0, 1.0)), 0.0);
  let fresnel = fresnelBase + (1.0 - fresnelBase) * pow(1.0 - cosTheta, 5.0);
  let rim = smoothstep(0.65, 1.0, factor) * inside;
  let spec = pow(max(0.0, 1.0 - factor), 4.0) * (0.25 + audio.y * 0.6);

  var bubbleColor = bubbleSample.rgb;
  bubbleColor = mix(bubbleColor, bubbleSample.rgb * interference * 1.25, 0.35 + fresnel * 0.35);
  bubbleColor = bubbleColor + vec3<f32>(1.0, 0.95, 0.92) * spec + interference * (rim * 0.2);

  let transmittance = exp(-drainedThickness * 0.35) * (0.85 + fresnel * 0.15);
  let finalColor = mix(src.rgb, bubbleColor, inside);
  let finalAlpha = clamp(mix(src.a, transmittance, inside) + inside * (0.14 + rim * 0.08), 0.08, 0.98);

  var out: BubbleEval;
  out.color = finalColor;
  out.inside = inside;
  out.drainedThickness = drainedThickness;
  out.spec = spec;
  out.alpha = finalAlpha;
  out.warpedUV = warpedUV;
  return out;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = vec2<f32>(gid.xy) / dims;
  let time = u.config.x;
  let rawMouse = u.zoom_config.yz;
  let aspect = dims.x / max(dims.y, 1.0);
  let audio = plasmaBuffer[0].xyz;

  // Exact parameter contracts
  let bubbleRadius = mix(0.10, 0.42, u.zoom_params.x);
  let magnification = mix(1.05, 4.0, u.zoom_params.y);
  let filmThickness = mix(0.25, 2.5, u.zoom_params.z) * (1.0 + audio.x * 0.25);
  let ior = mix(1.15, 1.65, u.zoom_params.w);

  let broadShimmer = (plasmaBuffer[2].x - 0.5) * 0.3;
  let fineShimmer = (plasmaBuffer[6].x - 0.5) * 0.3;

  // Critically-damped spring in extraBuffer[133..138]
  let isWriter = (gid.x == 0u && gid.y == 0u);
  let hasState = (arrayLength(&extraBuffer) > 138u);
  var springPos = rawMouse;
  if (hasState && extraBuffer[138] > 0.5) {
    springPos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  }

  if (isWriter && hasState) {
    let lastTime = extraBuffer[137];
    let dt = clamp(time - lastTime, 0.0, 0.05);
    var sPos = springPos;
    var sVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[138] < 0.5) {
      sPos = rawMouse;
      sVel = vec2<f32>(0.0);
    }
    let stiffness = 90.0;
    let damping = 18.97; // 2 * sqrt(90)
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
  let bubbleCenter = springPos;

  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let rippleCount = min(u32(u.config.y), 50u);

  // Film shockwaves
  var filmShock = 0.0;
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age < 0.0 || age > 1.2) { continue; }
    let clickDist = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
    let wavefront = age * 0.55;
    let ring = exp(-pow((clickDist - wavefront) * 16.0, 2.0));
    filmShock += ring * (1.0 - age / 1.2) * 0.45;
  }

  let mainEval = evalBubble(uv, src, bubbleCenter, bubbleRadius, magnification, filmThickness, ior, aspect, time, audio, broadShimmer, fineShimmer, filmShock);

  var finalColor = mainEval.color;
  var finalAlpha = mainEval.alpha;

  // Satellite bubbles on clicks
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age < 0.0 || age > 1.2) { continue; }
    let grow = smoothstep(0.0, 0.18, age);
    let pop = 1.0 - smoothstep(0.85, 1.2, age);
    let env = grow * pop;
    if (env <= 0.001) { continue; }
    let satRadius = 0.06 * (0.4 + 0.6 * grow);
    let satDistance = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
    if (satDistance > satRadius + 0.02) { continue; }
    let sat = evalBubble(uv, src, rp.xy, satRadius, 1.0 + (magnification - 1.0) * 0.5, filmThickness * 0.7, ior, aspect, time, audio, broadShimmer, fineShimmer, 0.0);
    let blend = sat.inside * env * 0.85;
    finalColor = mix(finalColor, sat.color, blend);
    finalAlpha = clamp(mix(finalAlpha, sat.alpha, blend), 0.08, 0.98);
  }

  let baseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, mainEval.warpedUV, 0.0).r;
  let outDepth = clamp(mix(textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r, baseDepth, mainEval.inside), 0.0, 1.0);

  // Exact load from dataTextureC
  let prevFrame = textureLoad(dataTextureC, coord, 0);
  finalColor = max(finalColor, prevFrame.rgb * (0.72 + mainEval.inside * 0.14));

  finalColor = acesFilm(finalColor);

  let outColor = vec4<f32>(finalColor, finalAlpha);
  textureStore(writeTexture, coord, outColor);
  textureStore(dataTextureA, coord, outColor);
  textureStore(writeDepthTexture, coord, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
}
