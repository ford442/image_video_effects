// Cyber Lattice Bilateral — Composer batch cyber/digital/glitch
// Edge-preserving bilateral smoothing inside a mouse-warped cyber grid.
// Spring cursor, held hue flip, capped ripples, exact C dream blend, ACES.

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

fn rgb2hsv(c: vec3<f32>) -> vec3<f32> {
  let K = vec4<f32>(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
  var p = mix(vec4<f32>(c.b, c.g, K.w, K.z), vec4<f32>(c.g, c.b, K.x, K.y), step(c.b, c.g));
  var q = mix(vec4<f32>(p.x, p.y, p.w, c.r), vec4<f32>(c.r, p.y, p.z, p.x), step(p.x, c.r));
  let d = q.x - min(q.w, q.y);
  let h = abs((q.w - q.y) / (6.0 * d + 1e-10) + K.x);
  return vec3<f32>(h, d, q.x);
}

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
  let K = vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0);
  let p = abs(fract(c.xxx + K.xyz) * 6.0 - 3.0);
  return c.z * mix(vec3<f32>(1.0), clamp(p - 1.0, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

  let coord = vec2<i32>(global_id.xy);
  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
  let pixelSize = 1.0 / res;
  let time = u.config.x;
  let aspect = res.x / max(res.y, 1.0);
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

  let gridScale = 10.0 + u.zoom_params.x * 50.0 * (1.0 + bass * 0.15);
  let distortStrength = u.zoom_params.y * (1.0 + mids * 0.2);
  let glowIntensity = u.zoom_params.z * (1.0 + treble * 0.25);
  let radius = mix(0.08, 0.45, u.zoom_params.w);

  let distVec = (uv - smoothMouse) * vec2<f32>(aspect, 1.0);
  let dist = length(distVec);
  let mouseInfluence = smoothstep(radius, 0.0, dist);

  let distortion = mouseInfluence * distortStrength * sin(time * 5.0 + bass * 2.0) * select(1.0, 1.35, held);
  let gridUV = uv + (uv - smoothMouse) * distortion;

  let gridX = abs(fract(gridUV.x * gridScale) - 0.5);
  let gridY = abs(fract(gridUV.y * gridScale) - 0.5);
  let gridLine = min(gridX, gridY);

  let thickness = mix(0.03, 0.08, glowIntensity);
  let currentThickness = thickness + mouseInfluence * 0.08;
  let gridMask = 1.0 - smoothstep(currentThickness, currentThickness + 0.05, gridLine);

  let spatialSigmaBase = mix(0.08, 0.9, 0.5 - u.zoom_params.y * 0.25);
  let colorSigma = mix(0.04, 0.8, 0.35 + mids * 0.2);
  let hueShiftAmt = mix(0.05, 0.35, u.zoom_params.z) * (1.0 + treble * 0.15);

  let mouseFactor = exp(-dist * dist * 8.0) * 0.5;
  let spatialSigma = mix(spatialSigmaBase, spatialSigmaBase * 0.2, mouseFactor);

  var rippleSharpness = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let rElapsed = time - ripple.z;
    if (rElapsed > 0.0 && rElapsed < 3.0) {
      let rDist = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
      let wave = exp(-pow((rDist - rElapsed * 0.3) * 12.0, 2.0));
      rippleSharpness = rippleSharpness + wave * (1.0 - rElapsed / 3.0);
    }
  }
  let finalSigma = max(spatialSigma * (1.0 - rippleSharpness * 0.8), 0.02);

  let center = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  var accumColor = vec3<f32>(0.0);
  var accumWeight = 0.0;
  let bRadius = i32(ceil(finalSigma * 2.5));
  let maxRadius = min(bRadius, 7);

  for (var dy = -maxRadius; dy <= maxRadius; dy++) {
    for (var dx = -maxRadius; dx <= maxRadius; dx++) {
      let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
      let neighbor = textureSampleLevel(readTexture, u_sampler, clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
      let spatialDist = length(vec2<f32>(f32(dx), f32(dy)));
      let spatialWeight = exp(-spatialDist * spatialDist / (2.0 * finalSigma * finalSigma + 0.001));
      let colorDist = length(neighbor.rgb - center.rgb);
      let rangeWeight = exp(-colorDist * colorDist / (2.0 * colorSigma * colorSigma + 0.001));
      let weight = spatialWeight * rangeWeight;
      accumColor += neighbor.rgb * weight;
      accumWeight += weight;
    }
  }

  var result = select(center.rgb, accumColor / accumWeight, accumWeight > 0.001);

  if (hueShiftAmt > 0.0) {
    let hsv = rgb2hsv(result);
    let newHue = fract(hsv.x + hueShiftAmt + dist * 0.3 + time * 0.05 + select(0.0, 0.15, held));
    result = hsv2rgb(vec3<f32>(newHue, hsv.y, hsv.z));
  }

  var glowColor = mix(vec3<f32>(0.0, 1.0, 1.0), vec3<f32>(1.0, 0.0, 1.0), select(0.0, 1.0, held));
  let totalGlow = glowIntensity * (0.5 + 0.5 * mouseInfluence) * (1.0 + bass * 0.2);

  var finalColor = mix(result, glowColor, gridMask * totalGlow);
  if (gridMask > 0.5) {
    finalColor = glowColor * totalGlow * 1.5;
  }

  let prevDream = textureLoad(dataTextureC, coord, 0).rgb;
  let dreamMix = mix(0.06, 0.22, u.zoom_params.z) * (1.0 - gridMask * 0.6);
  finalColor = mix(finalColor, prevDream, dreamMix);

  finalColor = acesToneMap(finalColor * (0.95 + bass * 0.06));

  let alpha = clamp(center.a * (1.0 - gridMask * 0.2) + gridMask * totalGlow * 0.35 + mouseInfluence * 0.1, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(finalColor, alpha));
  textureStore(dataTextureA, coord, vec4<f32>(finalColor, alpha));

  let depth = textureLoad(readDepthTexture, coord, 0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
