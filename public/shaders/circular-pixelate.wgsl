// Circular Pixelate — hexagonal compound lenslets with chromatic apertures.
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
const HEX_SIZE: vec2<f32> = vec2<f32>(1.0, 1.7320508);

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn getHex(p: vec2<f32>) -> vec4<f32> {
  let centerA = round(p / HEX_SIZE);
  let centerB = round((p - HEX_SIZE * 0.5) / HEX_SIZE) + 0.5;
  let offA = p - centerA * HEX_SIZE;
  let offB = p - centerB * HEX_SIZE;
  if (dot(offA, offA) < dot(offB, offB)) {
    return vec4<f32>(offA, centerA);
  }
  return vec4<f32>(offB, centerB);
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

fn spectrum(t: f32) -> vec3<f32> {
  return 0.55 + 0.45 * cos(TAU * (vec3<f32>(0.02, 0.35, 0.68) + t));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = vec2<f32>(gid.xy) / resolution;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let aspectVec = vec2<f32>(aspect, 1.0);
  let time = u.config.x;
  let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let held = u.zoom_config.w > 0.5;
  let bass = clamp(plasmaBuffer[0].x, 0.0, 2.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 2.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 2.0);

  let density = 10.0 + u.zoom_params.x * 100.0;
  let radiusParam = clamp(u.zoom_params.y, 0.0, 1.0);
  let hardness = clamp(u.zoom_params.z, 0.0, 1.0);
  let backgroundMix = clamp(u.zoom_params.w, 0.0, 1.0);
  let gridScale = vec2<f32>(density, density / max(aspect, 0.001));
  let hex = getHex(uv * gridScale);
  let local = hex.xy;
  let cellId = hex.zw;
  let cellCenterUV = (cellId * HEX_SIZE) / gridScale;

  let pointerDist = length((uv - mouse) * aspectVec);
  let heldDilation = smoothstep(0.34, 0.0, pointerDist) * select(0.18, 1.0, held);
  var clickWave = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 2.2) {
      let dist = length((uv - ripple.xy) * aspectVec);
      let front = age * (0.30 + bass * 0.08);
      clickWave += sin((dist - front) * 74.0) * exp(-abs(dist - front) * 33.0) * exp(-age * 1.35);
    }
  }

  let depth = textureLoad(readDepthTexture, coord, 0).r;
  let apertureRadius = clamp(0.10 + radiusParam * 0.46 + heldDilation * 0.13 +
                             bass * 0.035 + clickWave * 0.04, 0.045, 0.62);
  let distanceToCenter = length(local) * 1.15;
  let edgeWidth = mix(0.10, 0.008, hardness);
  let aperture = 1.0 - smoothstep(max(apertureRadius - edgeWidth, 0.0),
                                  apertureRadius + edgeWidth, distanceToCenter);
  let normalizedLocal = local / max(apertureRadius, 0.001);
  let lensZ = sqrt(max(1.0 - dot(normalizedLocal, normalizedLocal), 0.0));
  let lensNormal = normalize(vec3<f32>(normalizedLocal, lensZ + 0.001));
  let refraction = lensNormal.xy * (0.006 + depth * 0.014) * (1.0 + heldDilation * 0.7);
  let sampleBase = clamp(cellCenterUV + refraction, vec2<f32>(0.0), vec2<f32>(1.0));
  let chromaAmount = (0.0015 + mids * 0.003 + treble * 0.002) * aperture;
  let chromaDir = normalize(local + vec2<f32>(0.0001));
  let red = textureSampleLevel(readTexture, u_sampler,
                               clamp(sampleBase + chromaDir * chromaAmount, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let green = textureSampleLevel(readTexture, u_sampler, sampleBase, 0.0).g;
  let blue = textureSampleLevel(readTexture, u_sampler,
                                clamp(sampleBase - chromaDir * chromaAmount, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  let sampled = textureSampleLevel(readTexture, u_sampler, sampleBase, 0.0);
  let original = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let history = historyAt(sampleBase - chromaDir * clickWave * 0.004, resolution);

  let apertureAngle = atan2(local.y, local.x);
  let glintDirection = vec2<f32>(cos(time * 0.7 + mids), sin(time * 0.7 + mids));
  let glint = pow(max(dot(lensNormal.xy, glintDirection), 0.0), 18.0) * aperture * (0.25 + treble * 1.2);
  let rim = smoothstep(apertureRadius - edgeWidth * 3.0, apertureRadius, distanceToCenter) * aperture;
  let cellHue = hash12(cellId + 0.37) + apertureAngle / TAU + time * 0.025;
  let prism = spectrum(cellHue + mids * 0.12);
  var hdr = vec3<f32>(red, green, blue);
  hdr = mix(hdr, history.rgb, 0.035 + rim * 0.05);
  hdr += prism * glint * (0.35 + treble * 0.5);
  hdr += prism * rim * (0.08 + mids * 0.18);
  hdr += spectrum(cellHue + 0.33) * abs(clickWave) * aperture * 0.16;
  let lensDisplay = aces(max(hdr, vec3<f32>(0.0)));
  let effectAlpha = clamp(sampled.a * aperture + rim * 0.18 + glint * 0.16, 0.0, 1.0);
  let lenslet = vec4<f32>(lensDisplay, effectAlpha);
  let result = mix(original, lenslet, backgroundMix);

  textureStore(writeTexture, coord, result);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, result);
}
