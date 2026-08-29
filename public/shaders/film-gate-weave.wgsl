// Film Gate Weave — Composer batch cyber/digital/glitch cohort 3
// 35mm gate weave, scratch persistence via exact C load (A: rgb.r + scratch.g),
// spring registration anchor, held gate flutter, click splice flashes, ACES.

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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn dyeCloudGrain(uv: vec2<f32>, frameId: f32, grainSize: f32) -> f32 {
  let g1 = hash21(uv * 300.0 * grainSize + frameId * 0.3);
  let g2 = hash21(uv * 700.0 * grainSize + frameId * 0.7 + 17.3);
  let g3 = hash21(uv * 1200.0 * grainSize + frameId * 1.1 + 43.1);
  return g1 * 0.5 + g2 * 0.3 + g3 * 0.2;
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

  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

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
  let weaveAmount = u.zoom_params.x * 0.025;
  let dustAmount = u.zoom_params.y;
  let scratchAmount = u.zoom_params.z;
  let flickerAmount = u.zoom_params.w;

  let fps = 24.0;
  let frameId = floor(time * fps);
  let subFrame = fract(time * fps);

  let gateFlutter = sin(frameId * 0.47 + bass * 3.0) * 0.5 + 0.5;
  let regJitter = (hash21(vec2<f32>(frameId, 0.0)) - 0.5) * weaveAmount * 0.4;
  let intermittent = smoothstep(0.3, 0.7, gateFlutter) * weaveAmount * 0.3 * select(1.0, 1.6, held);
  let weave = sin(frameId * 0.37) * weaveAmount + regJitter + intermittent;

  let anchorPull = (smoothMouse - vec2<f32>(0.5)) * 0.015;
  let audioJitter = (hash21(vec2<f32>(time * fps, uv.y * 150.0)) - 0.5) * weaveAmount * bass * 0.6;
  let sampleUV = clamp(uv + vec2<f32>(anchorPull.x, weave + audioJitter), vec2<f32>(0.0), vec2<f32>(1.0));

  let color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
  let grainSize = mix(1.5, 0.6, depth);
  let grain = (dyeCloudGrain(uv, frameId, grainSize) - 0.5) * 0.08 * (1.0 + treble * 0.3);

  let dustNoise = hash21(floor(uv * resolution * 0.4) + frameId * 0.15);
  let dust = step(1.0 - dustAmount * 0.04, dustNoise) * 0.25;

  let prevScratch = textureLoad(dataTextureC, coord, 0).g;
  let scratchLine = hash21(vec2<f32>(floor(uv.x * resolution.x * 0.3), frameId));
  let newScratch = step(1.0 - scratchAmount * 0.015, scratchLine) * smoothstep(0.0, 0.08, uv.y) * smoothstep(1.0, 0.92, uv.y);
  let scratch = mix(prevScratch * 0.85, newScratch, 0.3);

  let hairLine = hash21(vec2<f32>(floor(uv.y * resolution.y), frameId * 0.5));
  let hair = step(1.0 - dustAmount * 0.008, hairLine) * 0.15 * smoothstep(0.1, 0.5, uv.x) * smoothstep(0.9, 0.5, uv.x);

  let splicePos = 0.33 + hash21(vec2<f32>(7.0, floor(time * 0.1))) * 0.34;
  var spliceTape = smoothstep(0.003, 0.0, abs(uv.y - splicePos)) * 0.4 * step(0.2, fract(time * 0.1));

  var clickFlash = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age >= 0.0 && age < 1.2) {
      let radius = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
      clickFlash = max(clickFlash, exp(-age * 2.5) * (1.0 - smoothstep(0.0, 0.12, radius)));
      spliceTape = max(spliceTape, clickFlash * 0.6);
    }
  }

  let flicker = 1.0 + (hash21(vec2<f32>(frameId, 0.0)) - 0.5) * flickerAmount * 0.35;
  let lensBreathe = 1.0 + sin(subFrame * 6.283) * weaveAmount * 0.5;
  let chromR = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV + vec2<f32>(0.003 * lensBreathe, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let chromB = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV - vec2<f32>(0.003 * lensBreathe, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;

  var rgb = vec3<f32>(chromR * flicker, color.g * flicker, chromB * flicker);
  rgb += vec3<f32>(grain) + vec3<f32>(dust) + vec3<f32>(scratch * 0.6) + vec3<f32>(hair);
  rgb += vec3<f32>(0.9, 0.85, 0.7) * spliceTape + vec3<f32>(1.0, 0.9, 0.7) * clickFlash * 0.3;
  rgb += vec3<f32>(1.0, 0.88, 0.72) * mids * 0.08;

  rgb = acesToneMap(rgb * 1.05);

  let weaveConfidence = 1.0 - abs(weave) / (weaveAmount + 0.001);
  let grainDensity = abs(grain) * 12.0 + dust + scratch + hair;
  let alpha = clamp(weaveConfidence * grainDensity * depth + color.a * 0.3 + clickFlash * 0.2 + bass * 0.04, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(rgb, alpha));
  textureStore(dataTextureA, coord, vec4<f32>(rgb.r, scratch, 0.0, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
