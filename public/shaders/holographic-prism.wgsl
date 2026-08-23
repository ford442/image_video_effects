// ═══════════════════════════════════════════════════════════════════
//  Holographic Prism v2
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
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
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn acesTonemap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn snellRefract(incident: vec2<f32>, n: vec2<f32>, n1: f32, n2: f32) -> vec2<f32> {
  let eta = n1 / n2;
  let cosI = clamp(-dot(incident, n), -1.0, 1.0);
  let sinT2 = eta * eta * (1.0 - cosI * cosI);
  let cosT = sqrt(max(0.0, 1.0 - sinT2));
  return incident * eta + n * (eta * cosI - cosT);
}

fn wavelengthToRGB(wavelength: f32) -> vec3<f32> {
  var c = vec3<f32>(0.0);
  if (wavelength < 440.0) {
    c = vec3<f32>(-(wavelength - 440.0) / 60.0, 0.0, 1.0);
  } else if (wavelength < 490.0) {
    c = vec3<f32>(0.0, (wavelength - 440.0) / 50.0, 1.0);
  } else if (wavelength < 510.0) {
    c = vec3<f32>(0.0, 1.0, -(wavelength - 510.0) / 20.0);
  } else if (wavelength < 580.0) {
    c = vec3<f32>((wavelength - 510.0) / 70.0, 1.0, 0.0);
  } else if (wavelength < 645.0) {
    c = vec3<f32>(1.0, -(wavelength - 645.0) / 65.0, 0.0);
  } else {
    c = vec3<f32>(1.0, 0.0, 0.0);
  }
  return clamp(c, vec3<f32>(0.0), vec3<f32>(1.0));
}

fn sdHexagon(p: vec2<f32>, r: f32) -> f32 {
    let k = vec3<f32>(-0.866025404, 0.5, 0.577350269);
    var q = abs(p);
    q -= 2.0 * min(dot(k.xy, q), 0.0) * k.xy;
    q -= vec2<f32>(clamp(q.x, -k.z * r, k.z * r), r);
    return length(q) * sign(q.y);
}

fn sdCircle(p: vec2<f32>, r: f32) -> f32 {
    return length(p) - r;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

  let time = u.config.x;
  
  if (gid.x == 0u && gid.y == 0u) {
    let dt = 0.016;
    let target = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    let is_held = u.zoom_config.w > 0.0;
    
    var pos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    var vel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    
    let k = 120.0;
    let b = 10.0;
    let force = (target - pos) * k - vel * b;
    vel += force * dt;
    pos += vel * dt;
    
    pos = clamp(pos, vec2<f32>(0.0), vec2<f32>(1.0));
    
    extraBuffer[133] = pos.x;
    extraBuffer[134] = pos.y;
    extraBuffer[135] = vel.x;
    extraBuffer[136] = vel.y;
    
    var held_val = extraBuffer[137];
    if (is_held) {
      held_val += dt * 3.0;
    } else {
      held_val -= dt * 2.0;
    }
    extraBuffer[137] = clamp(held_val, 0.0, 1.0);
  }

  let uv = vec2<f32>(gid.xy) / dims;
  let aspect = dims.x / dims.y;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
  let bass = audio.x;
  let mids = audio.y;
  let treble = audio.z;
  let bin1 = plasmaBuffer[1].x;
  
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let facets = max(3.0, floor(mix(3.0, 12.0, u.zoom_params.x)));
  let dispersion = u.zoom_params.y * 0.06;
  let rotationSpeed = u.zoom_params.z;
  let holoContrast = u.zoom_params.w;

  let smooth_mouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  let held_intensity = extraBuffer[137];

  let center = vec2<f32>(0.5, 0.5) + (smooth_mouse - 0.5) * 0.2 * (1.0 + depth * 0.5);
  let p = (uv - center) * vec2<f32>(aspect, 1.0);
  let dist = max(length(p), 0.001);
  let baseAngle = atan2(p.y, p.x);
  
  let shapeDist = mix(sdCircle(p, 0.2), sdHexagon(p, 0.2 + bass * 0.05), held_intensity);
  let shapeEdge = smoothstep(0.02, 0.0, abs(shapeDist));
  
  let prismRotation = baseAngle + time * rotationSpeed * (1.0 + bass * 0.5) + bass * 0.3;
  let facet = abs(fract(prismRotation / 6.28318 * facets) - 0.5) * 2.0;

  let n1 = 1.0;
  let n2 = 1.52 + held_intensity * 0.2;
  let prismNormal = vec2<f32>(cos(facet * 3.14159265 + 1.570796), sin(facet * 3.14159265 + 1.570796));
  let incident = normalize(p + vec2<f32>(0.001, 0.0));
  let refracted = snellRefract(incident, prismNormal, n1, n2);

  let facetWarp = vec2<f32>(refracted.x / aspect, refracted.y) * (0.025 + bass * 0.015 + held_intensity * 0.02) / (dist + 0.1);
  let holoSpeckle = hash12(floor(uv * 256.0 + fract(sin(time * 0.5) * 1000.0))) * 2.0 - 1.0;
  let speckleMask = smoothstep(0.35, 0.65, abs(holoSpeckle)) * holoContrast;

  let glitchJitter = vec2<f32>(
    sin(uv.y * 80.0 + time * (5.0 + treble * 8.0)),
    cos(uv.x * 90.0 + time * (4.0 + mids * 7.0))
  ) * 0.004 * holoContrast;

  let baseUV = clamp(uv + facetWarp + glitchJitter, vec2<f32>(0.001), vec2<f32>(0.999));

  let rShift = refracted * dispersion * 0.8 / (dist + 0.1);
  let bShift = refracted * dispersion * 1.2 / (dist + 0.1);

  let uvR = clamp(baseUV + vec2<f32>(rShift.x / aspect, rShift.y) * 0.03, vec2<f32>(0.001), vec2<f32>(0.999));
  let uvG = baseUV;
  let uvB = clamp(baseUV - vec2<f32>(bShift.x / aspect, bShift.y) * 0.03, vec2<f32>(0.001), vec2<f32>(0.999));

  let dataC = textureLoad(dataTextureC, vec2<i32>(gid.xy), 0);

  let sampled = vec3<f32>(
    textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r,
    textureSampleLevel(readTexture, u_sampler, uvG, 0.0).g,
    textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b
  );

  let wavelengthColor = wavelengthToRGB(mix(450.0, 700.0, facet));
  let caustic = wavelengthColor * exp(-dist * (2.2 + mids * 2.0)) * (0.2 + bass * 0.15) * (1.0 + dataC.r * 0.1);
  let interference = sin(dist * 60.0 - time * 3.0 + facet * 12.0) * 0.5 + 0.5;
  let holoFringe = caustic * interference * (0.5 + treble * 0.5) * speckleMask;

  let shardRing = smoothstep(0.08, 0.0, abs(dist - (0.18 + bass * 0.08))) + shapeEdge * 0.5;
  let bloom = vec3<f32>(1.0, 0.92, 0.55) * shardRing * (0.2 + mids * 0.3) * (1.0 + bin1 * 2.0);

  var clickFront = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
      let event = u.ripples[i];
      let age = max(time - event.z, 0.0);
      let r_dist = length((uv - event.xy) * vec2<f32>(aspect, 1.0));
      if (age < 2.0) {
          let wave = exp(-age * 1.8) * exp(-abs(r_dist - age * 0.38) * 58.0);
          clickFront += min(wave, 1.0);
      }
  }
  
  let clockRings = sin(length(uv - vec2<f32>(0.5)) * 95.0 - time * (5.0 + treble * 7.0));
  let spectral = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.094, 4.188) + clockRings * 3.0 + time * (0.8 + mids));

  let shapeGlow = spectral * shapeEdge * held_intensity;

  var finalColor = sampled * (0.75 + caustic.b * 0.15) + caustic * 0.7 + holoFringe + bloom + shapeGlow;
  finalColor += spectral * (abs(clockRings) * 0.1 + min(clickFront, 1.5) * 0.35);
  
  finalColor = acesTonemap(finalColor * 1.25);

  let dispersionAlpha = length(caustic) * 0.6 + shardRing * 0.3 + speckleMask * 0.15 + clickFront * 0.3 + shapeEdge * 0.5;
  let finalAlpha = clamp(dispersionAlpha * holoContrast + held_intensity * 0.2 + bass * 0.1, 0.0, 1.0);

  let finalDisplayRGBA = vec4<f32>(finalColor, finalAlpha);
  let depthOut = clamp(depth + shardRing * 0.06 + shapeEdge * 0.1, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(gid.xy), finalDisplayRGBA);
  textureStore(dataTextureA, vec2<i32>(gid.xy), finalDisplayRGBA);
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depthOut, 0.0, 0.0, 0.0));
}
