// Holographic Glitch — continuous phase corruption, peel interaction, rich trails.
// A/C stores tone-mapped display RGBA. B and extraBuffer are intentionally unused.

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

const TAU: f32 = 6.28318530718;

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let s = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), s.x),
             mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), s.x), s.y);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) /
               (x * (2.43 * x + 0.59) + 0.14),
               vec3<f32>(0.0), vec3<f32>(1.0));
}

fn historyCoord(uv: vec2<f32>, resolution: vec2<f32>) -> vec2<i32> {
  let hi = vec2<i32>(resolution) - vec2<i32>(1);
  return clamp(vec2<i32>(clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)) * resolution),
               vec2<i32>(0), hi);
}

fn historyAt(uv: vec2<f32>, resolution: vec2<f32>) -> vec4<f32> {
  return textureLoad(dataTextureC, historyCoord(uv, resolution), 0);
}

fn luma(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn spectrum(t: f32) -> vec3<f32> {
  return 0.52 + 0.48 * cos(TAU * (vec3<f32>(0.01, 0.34, 0.67) + t));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = vec2<f32>(gid.xy) / resolution;
  let aspectVec = vec2<f32>(resolution.x / max(resolution.y, 1.0), 1.0);
  let time = u.config.x;
  let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let held = u.zoom_config.w > 0.5;
  let bass = clamp(plasmaBuffer[0].x, 0.0, 2.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 2.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 2.0);
  let glitchIntensity = clamp(u.zoom_params.x, 0.0, 1.0);
  let holoIntensity = clamp(u.zoom_params.y, 0.0, 1.0);
  let rgbShift = clamp(u.zoom_params.z, 0.0, 1.0);
  let phaseInstability = clamp(u.zoom_params.w, 0.0, 1.0);

  let pointerDelta = (uv - mouse) * aspectVec;
  let pointerDist = length(pointerDelta);
  let pointerDir = pointerDelta / max(pointerDist, 0.0001);
  let peelMask = smoothstep(0.42, 0.0, pointerDist) * select(0.18, 1.0, held);
  let peelFold = sin(pointerDist * 38.0 - time * (2.0 + mids)) * peelMask;

  var desync = 0.0;
  var clickDirection = vec2<f32>(0.0);
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 2.5) {
      let delta = (uv - ripple.xy) * aspectVec;
      let dist = length(delta);
      let front = age * (0.34 + bass * 0.09);
      let pulse = sin((dist - front) * 83.0) * exp(-abs(dist - front) * 31.0) * exp(-age * 1.2);
      desync += pulse;
      clickDirection += delta / max(dist, 0.0001) * pulse;
    }
  }

  // Continuous row phase: spatially blocky, temporally smooth (no floor(time)).
  let row = floor(uv.y * (26.0 + glitchIntensity * 58.0));
  let phaseNoise = valueNoise(vec2<f32>(row * 0.173 + sin(time * 0.23),
                                        time * (0.7 + phaseInstability * 3.8) + row * 0.071));
  let carrier = sin(uv.y * resolution.y * (0.18 + phaseInstability * 0.72) +
                    time * (2.0 + treble * 5.0) + phaseNoise * TAU);
  let continuousShear = (phaseNoise - 0.5) * glitchIntensity * (0.025 + bass * 0.035) +
                        carrier * glitchIntensity * 0.004;
  let peelOffset = pointerDir / aspectVec * peelFold * (0.008 + holoIntensity * 0.018);
  let clickOffset = clickDirection / aspectVec * desync * glitchIntensity * 0.006;
  let depth = textureLoad(readDepthTexture, coord, 0).r;
  let warpedUV = clamp(uv + vec2<f32>(continuousShear, 0.0) + peelOffset + clickOffset +
                       vec2<f32>((depth - 0.5) * rgbShift * 0.004, 0.0),
                       vec2<f32>(0.0), vec2<f32>(1.0));

  let chromaDir = normalize((warpedUV - 0.5) * aspectVec + vec2<f32>(0.0001)) / aspectVec;
  let chromaAmount = rgbShift * (0.0015 + bass * 0.0035 + abs(desync) * 0.0025);
  let red = textureSampleLevel(readTexture, u_sampler,
                               clamp(warpedUV + chromaDir * chromaAmount, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let green = textureSampleLevel(readTexture, u_sampler, warpedUV, 0.0).g;
  let blue = textureSampleLevel(readTexture, u_sampler,
                                clamp(warpedUV - chromaDir * chromaAmount, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  let source = textureSampleLevel(readTexture, u_sampler, warpedUV, 0.0);

  let trailVelocity = vec2<f32>(continuousShear * 0.35, carrier * 0.0015) + peelOffset * 0.3;
  let historyR = historyAt(uv - trailVelocity + chromaDir * chromaAmount * 0.8, resolution);
  let historyG = historyAt(uv - trailVelocity * 0.65, resolution);
  let historyB = historyAt(uv - trailVelocity - chromaDir * chromaAmount * 0.8, resolution);
  let historyRGB = vec3<f32>(historyR.r, historyG.g, historyB.b);
  let historyAlpha = max(historyR.a, max(historyG.a, historyB.a));

  let interferencePhase = uv.x * (9.0 + holoIntensity * 20.0) +
                           uv.y * 5.0 + time * (0.55 + mids * 1.4) +
                           depth * 7.0 + peelFold * 2.5 + desync;
  let hologram = spectrum(interferencePhase / TAU) * (0.22 + holoIntensity * 1.15);
  let scan = 0.5 + 0.5 * sin(uv.y * resolution.y * 0.68 + time * (3.0 + treble * 7.0));
  let scanMask = mix(0.76, 1.08, scan) * (1.0 + treble * 0.12);
  let peelRim = pow(max(1.0 - pointerDist / 0.42, 0.0), 2.0) * abs(peelFold);
  var hdr = vec3<f32>(red, green, blue) * scanMask;
  hdr = mix(hdr, hologram + source.rgb * 0.24, holoIntensity * (0.38 + phaseNoise * 0.28));
  hdr += spectrum(time * 0.08 + pointerDist + mids * 0.12) * peelRim * (0.45 + treble * 0.7);
  hdr += spectrum(desync * 0.2 + time * 0.04) * abs(desync) * (0.22 + bass * 0.4);
  let trailMix = clamp(0.10 + phaseInstability * 0.30 + glitchIntensity * 0.12, 0.08, 0.48);
  hdr = mix(hdr, historyRGB * (0.90 + holoIntensity * 0.08), trailMix);
  let display = aces(max(hdr, vec3<f32>(0.0)));
  let alpha = clamp(source.a * 0.22 + luma(display) * (0.38 + holoIntensity * 0.36) +
                    historyAlpha * trailMix * 0.35 + peelRim * 0.18, 0.08, 0.98);
  let result = vec4<f32>(display, alpha);

  textureStore(writeTexture, coord, result);
  textureStore(dataTextureA, coord, result);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
