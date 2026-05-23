// ═══════════════════════════════════════════════════════════════════
//  VHS Tracking
//  Category: retro-glitch
//  Features: upgraded-rgba, depth-aware, audio-reactive
//  Complexity: High
//  Scientific: Capstan jitter, head switching, azimuth loss, chroma burst phase drift, and dropout streaks emulate VHS transport physics.
//  Upgraded: 2026-05-23
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;

fn hash12(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn gaussian_noise(seed: vec2<f32>) -> f32 {
  let u1 = max(hash12(seed), 1e-4);
  let u2 = hash12(seed + vec2<f32>(19.19, 73.73));
  return sqrt(-2.0 * log(u1)) * cos(2.0 * PI * u2);
}

fn clamp_uv(uv: vec2<f32>) -> vec2<f32> {
  return clamp(uv, vec2<f32>(0.001), vec2<f32>(0.999));
}

fn rgb_to_yiq(rgb: vec3<f32>) -> vec3<f32> {
  return vec3<f32>(
    dot(rgb, vec3<f32>(0.299, 0.587, 0.114)),
    dot(rgb, vec3<f32>(0.596, -0.275, -0.321)),
    dot(rgb, vec3<f32>(0.212, -0.523, 0.311))
  );
}

fn yiq_to_rgb(yiq: vec3<f32>) -> vec3<f32> {
  return vec3<f32>(
    yiq.x + 0.956 * yiq.y + 0.621 * yiq.z,
    yiq.x - 0.272 * yiq.y - 0.647 * yiq.z,
    yiq.x - 1.106 * yiq.y + 1.703 * yiq.z
  );
}

fn hue_shift(color: vec3<f32>, shift: f32) -> vec3<f32> {
  let k = vec3<f32>(0.57735026919);
  let cs = cos(shift);
  let sn = sin(shift);
  return color * cs + cross(k, color) * sn + k * dot(k, color) * (1.0 - cs);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (global_id.x >= size.x || global_id.y >= size.y) {
    return;
  }

  let coord = vec2<i32>(global_id.xy);
  let resolution = vec2<f32>(f32(size.x), f32(size.y));
  let texel = 1.0 / resolution;
  let uv = (vec2<f32>(f32(global_id.x), f32(global_id.y)) + 0.5) / resolution;
  let time = u.config.x;
  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
  let mouse = u.zoom_config.yz;
  let mouseDown = clamp(u.zoom_config.w, 0.0, 1.0);

  let rowState = textureLoad(dataTextureC, vec2<i32>(0, coord.y), 0);
  let prevWalk = (rowState.r * 2.0 - 1.0) * 0.02;
  let sigma = (0.00015 + u.zoom_params.x * 0.0012) * (1.0 + bass * 2.5);
  let walk = clamp(0.8 * prevWalk + gaussian_noise(vec2<f32>(f32(coord.y), floor(time * 60.0))) * sigma, -0.02, 0.02);
  let capstan = 0.002 * sin(2.0 * PI * 0.1 * time + f32(coord.y) * 0.03);
  let mouseTracking = mouseDown * (uv.y - mouse.y) * exp(-abs(uv.y - mouse.y) * 18.0) * (0.02 + bass * 0.035);
  let totalOffset = capstan + walk + mouseTracking;

  let sampleUV = clamp_uv(uv + vec2<f32>(totalOffset, 0.0));
  let source = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let thetaAz = u.zoom_params.y * 0.1 * PI / 180.0;
  let azimuthLoss = clamp(1.0 - cos(thetaAz), 0.0, 1.0);
  let chromaRadius = (1.0 + azimuthLoss * 14.0 + bass * 3.0) * texel.x;
  let lumaLeft = textureSampleLevel(readTexture, u_sampler, clamp_uv(sampleUV - vec2<f32>(texel.x, 0.0)), 0.0).rgb;
  let lumaRight = textureSampleLevel(readTexture, u_sampler, clamp_uv(sampleUV + vec2<f32>(texel.x, 0.0)), 0.0).rgb;
  let chromaLeft = textureSampleLevel(readTexture, u_sampler, clamp_uv(sampleUV - vec2<f32>(chromaRadius, 0.0)), 0.0).rgb;
  let chromaRight = textureSampleLevel(readTexture, u_sampler, clamp_uv(sampleUV + vec2<f32>(chromaRadius, 0.0)), 0.0).rgb;

  var yiq = rgb_to_yiq(source.rgb);
  let lumaBlur = dot((lumaLeft + source.rgb + lumaRight) / 3.0, vec3<f32>(0.299, 0.587, 0.114));
  let chromaBlur = rgb_to_yiq((chromaLeft + source.rgb + chromaRight) / 3.0);
  yiq.x = mix(yiq.x, lumaBlur, azimuthLoss * 0.9);
  let chromaMix = clamp(azimuthLoss * 1.8 + mids * 0.25, 0.0, 1.0);
  yiq.y = mix(yiq.y, chromaBlur.y, chromaMix);
  yiq.z = mix(yiq.z, chromaBlur.z, chromaMix);

  let phaseMag = (0.05 + u.zoom_params.w * 0.35 + bass * 0.25);
  let phaseShift = sin(time * 0.7 + uv.y * 120.0) * phaseMag;
  var color = hue_shift(yiq_to_rgb(yiq), phaseShift);

  let bandWidth = 5.0 / resolution.y;
  let headBand = max(
    smoothstep(bandWidth, 0.0, abs(uv.y - 0.0)),
    smoothstep(bandWidth, 0.0, abs(uv.y - 0.5))
  );
  let headNoise = (hash12(vec2<f32>(uv.x * resolution.x * 0.25, floor(time * 180.0))) - 0.5) * headBand;
  color = mix(color, vec3<f32>(0.02) + vec3<f32>(headNoise * 0.2), headBand * 0.9);

  let dropoutRate = clamp(u.zoom_params.z * (1.0 + bass * 1.5), 0.0, 1.0);
  let rowDrop = step(1.0 - dropoutRate * 0.08, hash12(vec2<f32>(f32(coord.y), floor(time * 50.0))));
  let seg = step(0.55, hash12(vec2<f32>(floor(uv.x * 18.0), f32(coord.y) + floor(time * 70.0))));
  let dropoutMask = rowDrop * seg * smoothstep(0.45, 0.0, abs(fract(uv.x * 18.0) - 0.5));
  let dropoutNoise = hash12(vec2<f32>(uv.x * 800.0, f32(coord.y) * 2.0 + floor(time * 120.0)));
  let dropoutColor = mix(vec3<f32>(0.0), vec3<f32>(1.0), step(0.5, dropoutNoise));
  color = mix(color, dropoutColor, dropoutMask * 0.95);

  let chromaSmear = textureSampleLevel(readTexture, u_sampler, clamp_uv(sampleUV - vec2<f32>((0.003 + bass * 0.004), 0.0)), 0.0).rgb;
  let smearYiq = rgb_to_yiq(chromaSmear);
  yiq = rgb_to_yiq(color);
  let smearMix = 0.32 + 0.28 * mids;
  yiq.y = mix(yiq.y, smearYiq.y, smearMix);
  yiq.z = mix(yiq.z, smearYiq.z, smearMix);
  color = yiq_to_rgb(yiq);

  let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
  color = mix(vec3<f32>(luma), color, 0.76 - 0.12 * azimuthLoss);
  color = color * vec3<f32>(1.04, 1.0, 0.88) + vec3<f32>(0.03, 0.018, 0.0);
  let scanline = 0.92 + 0.08 * sin(uv.y * resolution.y * PI);
  color = color * scanline;

  let alpha = clamp(source.a * (0.88 + 0.12 * luma) + dropoutMask * 0.08, 0.0, 1.0);
  textureStore(writeTexture, coord, vec4<f32>(clamp(color, vec3<f32>(0.0), vec3<f32>(1.0)), alpha));
  textureStore(dataTextureA, coord, vec4<f32>((walk / 0.02) * 0.5 + 0.5, dropoutMask, phaseShift * 0.5 + 0.5, headBand));
  textureStore(writeDepthTexture, coord, vec4<f32>(clamp(depth * 0.9 + headBand * 0.08 + dropoutMask * 0.06, 0.0, 1.0), 0.0, 0.0, 0.0));
}
