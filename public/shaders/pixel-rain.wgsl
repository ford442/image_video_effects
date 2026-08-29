// Pixel Rain — Composer batch cyber/digital/glitch
// Multi-layer parallax matrix rain: spring cursor, held repulsion,
// capped ripples, exact C trail fade, three-band audio, ACES + semantic alpha.

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
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn rainLayer(uv: vec2<f32>, time: f32, density: f32, speed: f32, depthT: f32, seed: f32) -> vec3<f32> {
  let colIndex = floor(uv.x * density + seed * 31.0);
  let colRand = fract(sin(colIndex * 12.9898 + seed * 78.233) * 43758.5453);
  let dropSpeed = (colRand * 0.6 + 0.4) * speed;
  let cell = floor(uv.y * density * 1.6);
  let phase = fract(uv.y + time * dropSpeed + colRand);
  let head = smoothstep(0.0, 0.04, phase) * exp(-phase * 5.0);
  let flick = step(0.35, fract(sin(cell * 1.7 + colIndex * 4.1 + floor(time * 6.0) * 0.13) * 9999.0));
  let bright = mix(0.18, 1.0, depthT) * head * flick;
  let tint = mix(vec3<f32>(0.0, 0.5, 0.45), vec3<f32>(0.3, 1.0, 0.4), depthT);
  return tint * bright;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(global_id.xy);
  let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
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
  if (global_id.x == 0u && global_id.y == 0u && hasSpring) {
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

  let speed = (u.zoom_params.x * 2.0 + 0.1) * (1.0 + bass * 0.6);
  let glitchIntensity = clamp(u.zoom_params.y * (1.0 + mids * 0.5), 0.0, 1.0);
  let density = u.zoom_params.z * 50.0 + 10.0 + treble * 20.0;
  let trailFade = u.zoom_params.w;

  let colIndex = floor(uv.x * density);
  let colRandom = fract(sin(colIndex * 12.9898) * 43758.5453);
  let dropSpeed = (colRandom * 0.5 + 0.5) * speed;
  let scrollY = time * dropSpeed;

  let mouseDist = length((uv - smoothMouse) * vec2<f32>(aspect, 1.0));
  let mouseForce = smoothstep(0.2, 0.0, mouseDist) * select(1.0, 1.5, held);

  var sampleUV = vec2<f32>(uv.x, fract(uv.y + scrollY));
  if (fract(uv.y * density * 0.5 + time) < glitchIntensity * 0.2) {
    sampleUV.x += (hash21(vec2<f32>(uv.y * 100.0, time)) - 0.5) * 0.05 * glitchIntensity;
  }
  if (mouseForce > 0.0) {
    let dir = normalize(uv - smoothMouse);
    sampleUV -= dir * mouseForce * 0.1 * glitchIntensity;
  }

  var rippleSplash = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age >= 0.0 && age < 1.0) {
      rippleSplash += smoothstep(0.1, 0.0, length((uv - rp.xy) * vec2<f32>(aspect, 1.0))) * (1.0 - age);
    }
  }

  let baseSample = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  var color = baseSample.rgb;
  color = mix(color, color * vec3<f32>(0.0, 1.0, 0.4) * 1.5, glitchIntensity * 0.6);

  let rainPhase = fract(uv.y + scrollY + colRandom);
  if (rainPhase < 0.05) {
    color += vec3<f32>(0.4, 1.0, 0.4) * glitchIntensity;
  }

  let fallBoost = 1.0 + bass * 0.6;
  color += rainLayer(uv, time, density * 1.8, speed * 0.45 * fallBoost, 0.25, 1.0);
  color += rainLayer(uv, time, density * 1.1, speed * 0.8 * fallBoost, 0.55, 2.0);
  color += rainLayer(uv, time, density * 0.6, speed * 1.4 * fallBoost, 1.0, 3.0);
  color += vec3<f32>(0.2, 0.2, 0.5) * mouseForce * 0.35;
  color += vec3<f32>(0.15, 0.9, 0.35) * rippleSplash * 0.4;

  let prev = textureLoad(dataTextureC, coord, 0).rgb;
  color = mix(color, prev, mix(0.08, 0.55, trailFade));

  color = acesToneMap(color * (0.95 + bass * 0.05));

  let alpha = clamp(baseSample.a * 0.85 + dot(color, vec3<f32>(0.299, 0.587, 0.114)) * 0.35 + mouseForce * 0.2 + rippleSplash * 0.15, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(dataTextureA, coord, vec4<f32>(color, alpha));

  let depth = textureLoad(readDepthTexture, coord, 0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
