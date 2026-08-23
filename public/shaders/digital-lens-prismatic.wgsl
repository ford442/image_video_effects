// ═══════════════════════════════════════════════════════════════════
//  digital-lens-prismatic — Batch 60
//  Cauchy dispersion lens: spring cursor, held squeeze, hex pixel grid,
//  iridescent rim, audio spectral spread, ACES tone map.
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

const PI: f32 = 3.14159265359;

fn cauchyIOR(wavelengthNm: f32, A: f32, B: f32) -> f32 {
  let lambdaUm = wavelengthNm * 0.001;
  return A + B / (lambdaUm * lambdaUm);
}

fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
  let t = clamp((lambda - 440.0) / (680.0 - 440.0), 0.0, 1.0);
  let r = smoothstep(0.5, 0.8, t) + smoothstep(0.0, 0.15, t) * 0.3;
  let g = 1.0 - abs(t - 0.4) * 3.0;
  let b = 1.0 - smoothstep(0.0, 0.4, t);
  return max(vec3<f32>(r, g, b), vec3<f32>(0.0));
}

fn refractThroughSurface(uv: vec2<f32>, center: vec2<f32>, ior: f32, curvature: f32, squeeze: f32) -> vec2<f32> {
  let toCenter = (uv - center) * vec2<f32>(1.0, 1.0 + squeeze * 0.3);
  let dist = length(toCenter);
  let lensStrength = curvature * 0.45;
  let offset = toCenter * (1.0 - 1.0 / ior) * lensStrength * (1.0 + dist * 2.2);
  return uv + offset;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hexEdge(uv: vec2<f32>, scale: f32) -> f32 {
  let p = uv * scale;
  let q = vec2<f32>(p.x * 1.7320508 + p.y, p.y * 2.0);
  let pf = fract(q);
  let d1 = length(pf - vec2<f32>(0.5, 0.5));
  let d2 = length(pf - vec2<f32>(0.0, 1.0));
  return 1.0 - smoothstep(0.01, 0.06, min(d1, d2));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let aspect = resolution.x / resolution.y;
  let held = u.zoom_config.w > 0.5;
  let mouse = u.zoom_config.yz;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let block_size = max(2.0, u.zoom_params.x * 50.0 + 2.0);
  let radius = u.zoom_params.y * 0.42 + 0.05;
  let grid_opacity = u.zoom_params.z;
  let cauchyB = mix(0.01, 0.1, u.zoom_params.w) * (1.0 + treble * 0.35);

  var smoothMouse = mouse;
  let hasSpring = arrayLength(&extraBuffer) > 138u;
  if (hasSpring) {
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

  let dist_vec = (uv - smoothMouse) * vec2<f32>(aspect, 1.0);
  let dist = length(dist_vec);
  let squeeze = select(0.0, 0.35, held);
  let mask = 1.0 - smoothstep(radius, radius + 0.06, dist);

  var ripplePulse = 0.0;
  let uvAspect = uv * vec2<f32>(aspect, 1.0);
  let rippleCount = min(u32(u.config.y), 50u);
  for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
    let rp = u.ripples[ri];
    let age = time - rp.z;
    if (age >= 0.0 && age < 1.0) {
      let rAspect = vec2<f32>(rp.x * aspect, rp.y);
      let rDist = length(uvAspect - rAspect);
      ripplePulse += smoothstep(0.14, 0.0, rDist) * (1.0 - age);
    }
  }

  var color: vec4<f32>;

  if (mask > 0.001 || ripplePulse > 0.05) {
    let blocks = resolution / block_size;
    let uv_quantized = floor(uv * blocks) / blocks + (0.5 / blocks);
    let lensCenter = smoothMouse;
    let glassCurvature = 0.85 + mids * 0.15;
    let glassThickness = 0.8;
    let spectralSat = 0.92 + bass * 0.15;

    let WAVELENGTHS = array<f32, 6>(420.0, 470.0, 520.0, 580.0, 630.0, 680.0);
    var finalColor = vec3<f32>(0.0);

    for (var i: i32 = 0; i < 6; i = i + 1) {
      let ior = cauchyIOR(WAVELENGTHS[i], 1.5, cauchyB);
      let refractedUV = refractThroughSurface(uv_quantized, lensCenter, ior, glassCurvature, squeeze);
      let wrappedUV = clamp(refractedUV, vec2<f32>(0.0), vec2<f32>(1.0));
      let sample = textureSampleLevel(readTexture, u_sampler, wrappedUV, 0.0);
      let absorption = exp(-glassThickness * (6.0 - f32(i)) * 0.12);
      let bandIntensity = dot(sample.rgb, wavelengthToRGB(WAVELENGTHS[i])) * absorption;
      finalColor += wavelengthToRGB(WAVELENGTHS[i]) * bandIntensity * spectralSat;
    }

    finalColor = finalColor / (1.0 + finalColor * 0.28);

    let uv_pixel = uv * resolution;
    let grid_x = step(block_size - 1.0, uv_pixel.x % block_size);
    let grid_y = step(block_size - 1.0, uv_pixel.y % block_size);
    let grid_line = max(grid_x, grid_y);
    let hex = hexEdge(uv, 18.0 + block_size);

    var lens_color = vec4<f32>(finalColor, 1.0);
    let tint = vec3<f32>(0.15, 1.0, 0.55);
    lens_color = vec4<f32>(mix(lens_color.rgb, lens_color.rgb * tint * 1.4, 0.35), lens_color.a);
    lens_color = mix(lens_color, vec4<f32>(0.0, 0.0, 0.0, 1.0), grid_line * grid_opacity);
    lens_color = mix(lens_color, vec4<f32>(wavelengthToRGB(520.0 + sin(time + dist * 8.0) * 80.0), 1.0), hex * 0.25);

    let rim = smoothstep(radius * 0.85, radius, dist) * (1.0 - mask);
    lens_color.rgb += wavelengthToRGB(580.0 + treble * 60.0) * rim * 0.6;

    let original = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let blendMask = clamp(mask + ripplePulse * 0.4, 0.0, 1.0);
    color = mix(original, lens_color, blendMask);
  } else {
    color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  }

  color.rgb = acesToneMap(color.rgb * (0.96 + bass * 0.06));
  let alpha = clamp(0.55 + mask * 0.35 + ripplePulse * 0.1, 0.0, 1.0);
  textureStore(writeTexture, coord, vec4<f32>(color.rgb, alpha));
  textureStore(dataTextureA, coord, vec4<f32>(mask, dist, cauchyB, alpha));

  let depth = textureLoad(readDepthTexture, coord, 0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
