// Pixelation Drift — Composer batch cyber/digital/glitch
// Audio-reactive mosaic drift + chromatic pixels: spring cursor, held focus,
// capped ripples, exact C persistence, three-band audio, ACES + semantic alpha.

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

fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
  p3 += dot(p3, vec3<f32>(p3.y, p3.z, p3.x) + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash21(i + vec2<f32>(0.0, 0.0)), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y
  );
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }
  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / resolution;
  let time = u.config.x;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let held = u.zoom_config.w > 0.5;
  let mouse = u.zoom_config.yz;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  var smoothMouse = mouse;
  let hasSpring = arrayLength(&extraBuffer) > 138u;
  if (hasSpring && extraBuffer[138] > 0.5) {
    smoothMouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  }
  if (gid.x == 0u && gid.y == 0u && hasSpring) {
    var springPos = smoothMouse;
    var springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[138] <= 0.5) {
      springPos = mouse;
      springVel = vec2<f32>(0.0);
    } else {
      let dt = clamp(time - extraBuffer[137], 0.001, 0.05);
      let omega = 9.0;
      let accel = (mouse - springPos) * (omega * omega) - springVel * (2.0 * omega);
      springVel += accel * dt;
      springPos += springVel * dt;
    }
    extraBuffer[133] = springPos.x;
    extraBuffer[134] = springPos.y;
    extraBuffer[135] = springVel.x;
    extraBuffer[136] = springVel.y;
    extraBuffer[137] = time;
    extraBuffer[138] = 1.0;
    smoothMouse = springPos;
  }

  let depth = textureLoad(readDepthTexture, coord, 0).r;
  let basePixelSize = max(u.zoom_params.x, 0.01) * 100.0 * (1.0 + bass * 0.3);
  let driftSpeed = u.zoom_params.y * (1.0 + mids * 0.2);
  let colorBleed = u.zoom_params.z;
  let depthInfluence = u.zoom_params.w;

  let depthFactor = mix(1.0, 1.0 - depth * 0.7, depthInfluence);
  let mouseDeltaAspect = (uv - smoothMouse) * vec2<f32>(aspect, 1.0);
  let mouseDistance = length(mouseDeltaAspect);
  let focusLens = exp(-mouseDistance * mouseDistance * 18.0);

  var clickPixelPulse = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
    let ripple = u.ripples[ri];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 1.6) {
      let clickDistance = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
      clickPixelPulse += exp(-abs(clickDistance - age * 0.34) * 26.0) * exp(-age * 1.6);
    }
  }

  let heldFocus = select(1.0, 0.75, held);
  let pixelSize = max(basePixelSize * depthFactor * mix(1.0, 0.45 * heldFocus, focusLens) * (1.0 + clickPixelPulse * 0.8), 1.0);

  let regionCoord = vec2<u32>(floor(clamp(uv * 8.0, vec2<f32>(0.0), vec2<f32>(7.0))));
  let regionVoice = plasmaBuffer[(regionCoord.x + regionCoord.y) % 8u + 1u].x;

  let driftOffset = vec2<f32>(
    noise(uv * 5.0 + vec2<f32>(time * driftSpeed * 0.2, 0.0)),
    noise(uv * 5.0 + vec2<f32>(0.0, time * driftSpeed * 0.2))
  ) * 2.0 - 1.0;

  let safeMouseDir = mouseDeltaAspect / max(mouseDistance, 0.001);
  let mouseSwirl = vec2<f32>(-safeMouseDir.y / aspect, safeMouseDir.x) * focusLens * select(0.0, 0.012, held);

  let driftedUV = uv + driftOffset * 0.02 * driftSpeed * (1.0 + regionVoice * 0.3) + mouseSwirl;
  let pixelatedUV = clamp(floor(driftedUV * resolution / pixelSize) * pixelSize / resolution, vec2<f32>(0.0), vec2<f32>(1.0));

  let chromaShift = pixelSize / resolution.x * treble * 0.5;
  let rUV = clamp(pixelatedUV + vec2<f32>(chromaShift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
  let gUV = pixelatedUV;
  let bUV = clamp(pixelatedUV - vec2<f32>(chromaShift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));

  let gSample = textureSampleLevel(readTexture, u_sampler, gUV, 0.0);
  var color = vec3<f32>(
    textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r,
    gSample.g,
    textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b
  );
  var baseAlpha = gSample.a;

  if (colorBleed > 0.01) {
    let bleedOffset = vec2<f32>(
      sin(time * 0.5 + uv.y * 10.0 + bass * 3.14),
      cos(time * 0.5 + uv.x * 10.0 + mids * 3.14)
    ) * pixelSize / resolution * colorBleed * 2.0;
    let bleedColor = textureSampleLevel(readTexture, u_sampler, clamp(pixelatedUV + bleedOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    color = mix(color, bleedColor.rgb, colorBleed * 0.3);
    baseAlpha = mix(baseAlpha, bleedColor.a, colorBleed * 0.3);
  }

  let pixelCenter = (floor(driftedUV * resolution / pixelSize) + 0.5) * pixelSize / resolution;
  let edgeGlow = smoothstep(pixelSize * 0.4, pixelSize * 0.5, length((driftedUV - pixelCenter) * resolution));
  color = mix(color, color * 1.2, edgeGlow * 0.1);

  let prev = textureLoad(dataTextureC, coord, 0);
  let persistence = clamp(0.12 + bass * 0.05 + regionVoice * 0.03, 0.0, 0.35);
  color = mix(color, prev.rgb, persistence);

  color = acesToneMap(color * (0.95 + bass * 0.04));

  let alpha = clamp(baseAlpha * (1.0 - edgeGlow * 0.2) + bass * 0.05 + clickPixelPulse * 0.1, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(dataTextureA, coord, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
