// ═══════════════════════════════════════════════════════════════════
//  Interactive Halftone Spin — Batch 58E
//  CMYK screens with held shear, ink conveyors, click splats,
//  oil-slick registration glow, three-band audio.
//  A remains [C, M, Y, K] coverage.
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

fn rgb2cmyk(c: vec3<f32>) -> vec4<f32> {
  var k = 1.0 - max(max(c.r, c.g), c.b);
  if (k >= 1.0) {
    return vec4<f32>(0.0, 0.0, 0.0, 1.0);
  }
  let invK = 1.0 / (1.0 - k);
  return vec4<f32>((1.0 - c.r - k) * invK, (1.0 - c.g - k) * invK, (1.0 - c.b - k) * invK, k);
}

fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
  let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  let p = abs(fract(hsv.xxx + k.xyz) * 6.0 - k.www);
  return hsv.z * mix(k.xxx, clamp(p - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), hsv.y);
}

fn rotatedGrid(uv: vec2<f32>, angle: f32, scale: f32) -> f32 {
  let s = sin(angle);
  let c = cos(angle);
  let st = mat2x2<f32>(c, -s, s, c) * uv * scale;
  let cell = fract(st) - 0.5;
  return length(cell) * 2.0;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let pixel = vec2<i32>(global_id.xy);
  var uv = vec2<f32>(global_id.xy) / max(resolution, vec2<f32>(1.0));
  let aspect = resolution.x / max(resolution.y, 1.0);
  let uv_aspect = vec2<f32>(uv.x * aspect, uv.y);
  let mouse = u.zoom_config.yz;
  let mouse_aspect = vec2<f32>(mouse.x * aspect, mouse.y);
  let held = f32(u.zoom_config.w > 0.5);
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let prev = textureLoad(dataTextureC, pixel, 0);

  let scaleParam = u.zoom_params.x * 200.0 + 20.0;
  let rotParam = u.zoom_params.y * 3.14159 * 2.0;
  let spreadParam = u.zoom_params.z;
  let contrastParam = u.zoom_params.w * 2.0 + 0.5;

  let dist = distance(uv_aspect, mouse_aspect);
  let influence = smoothstep(0.4, 0.0, dist) * mix(1.0, 1.45, held);
  let extraRot = influence * rotParam + time * 0.15 * u.zoom_params.y * (1.0 + bass * 0.4);
  let shear = vec2<f32>(held * (mouse.x - 0.5) * 0.08, held * (mouse.y - 0.5) * 0.05);
  let uvSpin = uv_aspect + shear;

  var click = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age >= 0.0 && age < 1.4) {
      let d = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
      click = max(click, exp(-abs(d - age * 0.4) * 40.0) * (1.0 - age / 1.4));
    }
  }

  let texColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let contrastColor = (texColor - 0.5) * contrastParam + 0.5;
  var cmyk = rgb2cmyk(clamp(contrastColor, vec3<f32>(0.0), vec3<f32>(1.0)));
  cmyk = vec4<f32>(
    clamp(cmyk.x * (1.0 + bass * 0.15 + click * 0.2), 0.0, 1.0),
    clamp(cmyk.y * (1.0 + mids * 0.12), 0.0, 1.0),
    clamp(cmyk.z * (1.0 + treble * 0.1), 0.0, 1.0),
    cmyk.w
  );

  var s = spreadParam + influence;
  let angC = 0.261 + extraRot * 1.0;
  let angM = 1.309 + extraRot * 1.5 * s;
  let angY = 0.0 + extraRot * 0.5;
  let angK = 0.785 - extraRot * 1.0 * s;
  let conveyor = 0.08 * sin(time * (3.0 + bass * 2.0) + uv_aspect.y * 12.0);

  let pC = rotatedGrid(uvSpin, angC, scaleParam + conveyor * 8.0);
  let pM = rotatedGrid(uvSpin, angM, scaleParam);
  let pY = rotatedGrid(uvSpin, angY, scaleParam - conveyor * 6.0);
  let pK = rotatedGrid(uvSpin, angK, scaleParam);

  let outC = step(pC, sqrt(cmyk.x));
  let outM = step(pM, sqrt(cmyk.y));
  let outY = step(pY, sqrt(cmyk.z));
  let outK = step(pK, sqrt(cmyk.w));

  var finalRGB = vec3<f32>(1.0);
  finalRGB.r = finalRGB.r * (1.0 - outC);
  finalRGB.g = finalRGB.g * (1.0 - outM);
  finalRGB.b = finalRGB.b * (1.0 - outY);
  finalRGB = finalRGB * (1.0 - outK);

  let packets = pow(max(0.0, sin(uv_aspect.x * 24.0 - time * (7.0 + mids * 4.0))), 12.0);
  let slick = hsv2rgb(vec3<f32>(fract(0.12 + influence * 0.2 + mids * 0.15 + time * 0.07), 0.7, 1.0));
  finalRGB = mix(finalRGB, finalRGB * slick * 1.15, 0.12 + treble * 0.15);
  finalRGB += slick * (click * 0.45 + packets * 0.12 * influence + held * influence * 0.08);
  finalRGB = mix(finalRGB, prev.rgb, 0.1);
  finalRGB = clamp(finalRGB, vec3<f32>(0.0), vec3<f32>(1.0));

  let coverage = vec4<f32>(outC, outM, outY, outK);
  let persist = mix(coverage, prev, 0.12);
  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  textureStore(writeTexture, pixel, vec4<f32>(finalRGB, 1.0));
  textureStore(dataTextureA, pixel, persist);
  textureStore(writeDepthTexture, pixel, vec4<f32>(clamp(depth + click * 0.05, 0.0, 1.0), 0.0, 0.0, 0.0));
}
