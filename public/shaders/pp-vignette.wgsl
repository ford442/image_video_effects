// ═══════════════════════════════════════════════════════════════════
//  PP Vignette
//  Category: post-processing
//  Features: mouse-driven, audio-reactive, upgraded-rgba, fast-motion
//  Complexity: High
//  Upgraded: 2026-09-06
//  A packing: ACES display RGBA
//  Motion: mobile anamorphic vignette aperture + exposure ripple blooms
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
  zoom_params: vec4<f32>,  // x=VignetteIntensity, y=GrainIntensity, z=ColorStyle, w=BlendMode
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn getLuma(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
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
  let binA = plasmaBuffer[2].x;

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
      let omega = 12.0;
      vel += ((mouse - pos) * (omega * omega) - vel * (2.0 * omega)) * dt;
      vel = clamp(vel, vec2<f32>(-3.5), vec2<f32>(3.5));
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
  let vignetteIntensity = u.zoom_params.x;
  let grainIntensity = u.zoom_params.y;
  let colorStyle = u.zoom_params.z;
  let blendMode = u.zoom_params.w;

  // Depth sampling
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthFade = mix(0.7, 1.3, depth);

  // Optical center blend between screen center (0.5, 0.5) and interactive spring cursor
  let apertureCenter = mix(vec2<f32>(0.5), spring, 0.45);
  let relCoord = (uv - apertureCenter) * aspectVec;
  let dist = length(relCoord);

  // Click ripple exposure blooms
  var rippleBloom = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let age = time - r.z;
    if (age > 0.0 && age < 2.4) {
      let d = length((uv - r.xy) * aspectVec);
      let ring = exp(-abs(d - age * 0.44) * 26.0) * exp(-age * 1.4);
      rippleBloom += ring;
    }
  }

  // Falloff calculation with audio breathing
  let breathe = 1.0 - bass * 0.15 + select(0.0, 0.12, held);
  let effectiveFalloff = mix(0.3, 1.8, vignetteIntensity) * breathe;
  let vigMask = 1.0 - smoothstep(0.35 / effectiveFalloff, 0.95 / effectiveFalloff, dist);

  // Sample source texture
  let source = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let srcLuma = getLuma(source);

  // Natural triangular film grain
  let g1 = hash12(uv * dims + vec2<f32>(time * 12.0, time * 7.0));
  let g2 = hash12(uv * dims + vec2<f32>(time * 5.0 + 19.3, time * 13.0 + 47.1));
  let triGrain = (g1 + g2 - 1.0) * mix(0.0, 0.14, grainIntensity) * (1.0 + treble * 0.5);

  // Color grading styles
  let sepia = vec3<f32>(
    dot(source, vec3<f32>(0.393, 0.769, 0.189)),
    dot(source, vec3<f32>(0.349, 0.686, 0.168)),
    dot(source, vec3<f32>(0.272, 0.534, 0.131))
  );
  let warmGrade = source * vec3<f32>(1.12, 1.02, 0.86) + vec3<f32>(0.04, 0.02, 0.0);
  let coolGrade = vec3<f32>(source.r * 0.85, source.g * 1.05, source.b * 1.25) + vec3<f32>(0.0, 0.03, 0.06);

  var graded = source;
  if (colorStyle < 0.33) {
    let tStyle = colorStyle / 0.33;
    graded = mix(source, sepia, tStyle);
  } else if (colorStyle < 0.66) {
    let tStyle = (colorStyle - 0.33) / 0.33;
    graded = mix(sepia, warmGrade, tStyle);
  } else {
    let tStyle = (colorStyle - 0.66) / 0.34;
    graded = mix(warmGrade, coolGrade, tStyle);
  }
  graded = mix(graded, graded * (1.0 + mids * 0.25), 0.5);

  // Blend modes for the vignette
  var vignetted = graded;
  if (blendMode < 0.5) {
    // Standard photographic falloff
    let tBlend = blendMode / 0.5;
    let standardVig = graded * vigMask;
    let darkFog = mix(graded * vigMask, vec3<f32>(0.02, 0.02, 0.03), (1.0 - vigMask) * 0.85);
    vignetted = mix(standardVig, darkFog, tBlend);
  } else {
    // Bleach bypass / high-contrast edge crush
    let tBlend = (blendMode - 0.5) / 0.5;
    let darkFog = mix(graded * vigMask, vec3<f32>(0.02, 0.02, 0.03), (1.0 - vigMask) * 0.85);
    let bleach = mix(graded, vec3<f32>(srcLuma), 0.4) * (vigMask * 1.2 + 0.1);
    vignetted = mix(darkFog, bleach, tBlend);
  }

  // Inject grain and ripple flash bloom
  let bloomTint = vec3<f32>(1.0, 0.92, 0.82) * rippleBloom * 0.45;
  var hdr = vignetted + vec3<f32>(triGrain) + bloomTint;

  // Exact previous frame history load from dataTextureC for temporal anti-strobe
  let hist = textureLoad(dataTextureC, coord, 0);
  let feedbackWeight = mix(0.04, 0.18, vigMask);
  hdr = mix(hdr, hist.rgb, feedbackWeight);

  let finalRGB = acesToneMap(hdr);
  let semanticAlpha = clamp(vigMask * depthFade + rippleBloom * 0.2 + 0.2, 0.0, 1.0);
  let outCol = vec4<f32>(finalRGB, semanticAlpha);

  textureStore(writeTexture, coord, outCol);
  textureStore(dataTextureA, coord, outCol);
  textureStore(writeDepthTexture, coord, vec4<f32>(clamp(depth * vigMask, 0.0, 1.0), 0.0, 0.0, 0.0));
}
