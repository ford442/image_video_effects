// ═══════════════════════════════════════════════════════════════════
//  Static Reveal v3 (VCR Tracking Edition)
//  Category: image
//  Features: mouse-driven, audio-reactive, multi-layer-static, temporal,
//            VCR tracking noise, horizontal hold instability, snow patterns,
//            signal acquisition phase, chrominance noise
//  Upgraded: 2026-08-21 (Batch 42 - VCR Tracking)
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
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash12(i), hash12(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y
  );
}

fn perlinOctaves(p: vec2<f32>, t: f32) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var pp = p;
  for (var i = 0; i < 4; i = i + 1) {
    v += a * noise2(pp + t * 0.05 * f32(i + 1));
    pp = pp * 2.03;
    a *= 0.5;
  }
  return v;
}

fn blueNoise(p: vec2<f32>) -> f32 {
  let bayer = hash12(p * 73.0) * 0.25 + hash12(p * 137.0) * 0.25 +
              hash12(p * 251.0) * 0.25 + hash12(p * 379.0) * 0.25;
  return bayer;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let uv = vec2<f32>(global_id.xy) / u.config.zw;
  let aspect = u.config.z / u.config.w;
  let aspectVec = vec2<f32>(aspect, 1.0);
  let time = u.config.x;

  let decaySpeed = u.zoom_params.x * 0.05;
  let brushRadius = u.zoom_params.y * 0.3 + 0.05;
  let noiseIntensity = clamp(u.zoom_params.z + treble * 0.2, 0.0, 1.0);
  let noiseScale = 30.0 + u.zoom_params.w * 250.0;

  let mouse = u.zoom_config.yz;
  let revealThreshold = u.zoom_config.y;
  let dist = distance((uv - mouse) * aspectVec, vec2<f32>(0.0));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthDecay = mix(0.7, 1.3, depth);
  
  let reactiveRadius = brushRadius * (1.0 + bass * 0.3 + mids * 0.1);
  let prevMask = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).a; // Using alpha for mask
  let brush = smoothstep(reactiveRadius, reactiveRadius * 0.5, dist);
  let mask = clamp(max(prevMask - decaySpeed * depthDecay, brush), 0.0, 1.0);

  let staticTime = time * 2.0;
  
  // VCR Tracking noise - horizontal bands
  let trackingOffset = hash12(vec2<f32>(floor(time * 30.0), floor(uv.y * 50.0))) * 0.05;
  let trackingBand = smoothstep(0.0, 0.1, abs(sin(time * 0.5 + uv.y * 10.0)));
  
  // Horizontal hold instability
  let hHold = sin(uv.y * 30.0 + time * 10.0) * 0.02 * (1.0 - mask) * bass;
  let dUV = uv + vec2<f32>(hHold + trackingOffset * trackingBand * (1.0 - mask), 0.0);

  // Snow pattern
  let snowHash = hash22(dUV * 500.0 + time);
  let snow = dot(snowHash, vec2<f32>(0.5)) * noiseIntensity;
  
  // Signal acquisition phase (bright flashes)
  let acqFlash = smoothstep(0.95, 1.0, sin(time * 2.0)) * (1.0 - mask);
  
  let staticFlicker = 1.0 + bass * 0.6 + mids * 0.2;
  
  // Chrominance noise
  let chromaNoiseYUV = vec3<f32>(
      perlinOctaves(dUV * noiseScale, staticTime),
      perlinOctaves(dUV * noiseScale * 0.8 + 10.0, staticTime * 1.1),
      perlinOctaves(dUV * noiseScale * 1.2 - 20.0, staticTime * 0.9)
  );
  
  let grainR = snow + chromaNoiseYUV.y * 0.1;
  let grainG = snow;
  let grainB = snow + chromaNoiseYUV.z * 0.1;
  let grainColor = vec3<f32>(grainR, grainG, grainB) * staticFlicker;

  let vig = smoothstep(1.0, 0.3, length(uv - 0.5) * 1.5);
  let unrevealedVig = (1.0 - mask) * vig;
  
  // Tinted snow based on signal loss
  let tintedGrain = mix(grainColor, grainColor * vec3<f32>(0.5, 0.6, 0.9), unrevealedVig) + acqFlash * 0.2;

  let videoColor = textureSampleLevel(readTexture, u_sampler, dUV, 0.0).rgb;
  let revealBias = smoothstep(revealThreshold, revealThreshold + 0.2, mask);
  
  // Chrominance shift in video color based on tracking
  let shiftAmount = trackingBand * (1.0 - revealBias) * 0.02;
  let videoColorShiftR = textureSampleLevel(readTexture, u_sampler, dUV + vec2<f32>(shiftAmount, 0.0), 0.0).r;
  let videoColorShiftB = textureSampleLevel(readTexture, u_sampler, dUV - vec2<f32>(shiftAmount, 0.0), 0.0).b;
  let finalVideoColor = vec3<f32>(videoColorShiftR, videoColor.g, videoColorShiftB);

  var finalColor = mix(tintedGrain, finalVideoColor, revealBias);

  finalColor = finalColor + vec3<f32>(unrevealedVig * 0.08, unrevealedVig * 0.05, 0.0);
  finalColor = acesToneMap(finalColor * 1.1);

  let staticStrength = 1.0 - revealBias;
  let alpha = clamp(mask * (1.0 - staticStrength * 0.7) + 0.15 + acqFlash * 0.5, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
  textureStore(dataTextureA, global_id.xy, vec4<f32>(finalColor, mask)); // store mask in alpha
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
