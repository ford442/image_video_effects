// ═══════════════════════════════════════════════════════════════════
//  Interactive Halftone Spin
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-04
//  Ideas: rotational arc-smear of spinning screens; honest CMYK after-image decoded from C coverage
//  A packing: [C, M, Y, K] screen coverage with light persistence (C is decoded as ink, not RGB)
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

// Subtractive print of a CMYK coverage set on white paper.
fn cmyk2rgb(cov: vec4<f32>) -> vec3<f32> {
  return (vec3<f32>(1.0) - clamp(cov.xyz, vec3<f32>(0.0), vec3<f32>(1.0))) * (1.0 - clamp(cov.w, 0.0, 1.0));
}

fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
  let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  let p = abs(fract(hsv.xxx + k.xyz) * 6.0 - k.www);
  return hsv.z * mix(k.xxx, clamp(p - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), hsv.y);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn rotatedGrid(uv: vec2<f32>, angle: f32, scale: f32) -> f32 {
  let s = sin(angle);
  let c = cos(angle);
  let st = mat2x2<f32>(c, -s, s, c) * uv * scale;
  let cell = fract(st) - 0.5;
  return length(cell) * 2.0;
}

// Idea 1: a spinning screen is exposed over a short arc, not a single angle.
// Three taps across ±smear radians average the dot into a tangential streak
// that grows with distance from the rotation pivot, exactly as a real spin blur.
fn smearedDot(uv: vec2<f32>, angle: f32, scale: f32, amount: f32, smear: f32) -> f32 {
  let t = sqrt(clamp(amount, 0.0, 1.0));
  let a = step(rotatedGrid(uv, angle - smear, scale), t);
  let b = step(rotatedGrid(uv, angle, scale), t);
  let c = step(rotatedGrid(uv, angle + smear, scale), t);
  return (a + b * 2.0 + c) * 0.25;
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

  // Shutter arc: the drift spin rate plus the cursor-driven twist, which is
  // fastest while the pointer is held over the screen.
  let spinRate = 0.15 * u.zoom_params.y * (1.0 + bass * 0.4) + influence * rotParam * (0.02 + held * 0.05);
  let arc = clamp(spinRate * 0.35, 0.0, 0.12);

  let conveyor = 0.08 * sin(time * (3.0 + bass * 2.0) + uv_aspect.y * 12.0);
  let outC = smearedDot(uvSpin, angC, scaleParam + conveyor * 8.0, cmyk.x, arc * 1.0);
  let outM = smearedDot(uvSpin, angM, scaleParam, cmyk.y, arc * 1.5 * max(s, 0.2));
  let outY = smearedDot(uvSpin, angY, scaleParam - conveyor * 6.0, cmyk.z, arc * 0.5);
  let outK = smearedDot(uvSpin, angK, scaleParam, cmyk.w, arc * 1.0 * max(s, 0.2));
  let coverage = vec4<f32>(outC, outM, outY, outK);

  var finalRGB = cmyk2rgb(coverage);

  let packets = pow(max(0.0, sin(uv_aspect.x * 24.0 - time * (7.0 + mids * 4.0))), 12.0);
  let slick = hsv2rgb(vec3<f32>(fract(0.12 + influence * 0.2 + mids * 0.15 + time * 0.07), 0.7, 1.0));
  finalRGB = mix(finalRGB, finalRGB * slick * 1.15, 0.12 + treble * 0.15);
  finalRGB += slick * (click * 0.45 + packets * 0.12 * influence + held * influence * 0.08);

  // Idea 2: C holds last frame's ink coverage. Print it as ink and lay it
  // under the new screen; where the screens have rotated away, the old dots
  // remain as a faint CMYK after-image instead of a misread RGB smear.
  let ghostRGB = cmyk2rgb(prev);
  let moved = clamp(length(prev - coverage) * 0.5, 0.0, 1.0);
  let ghostAmt = 0.10 + moved * (0.12 + held * influence * 0.18);
  finalRGB = mix(finalRGB, min(finalRGB, ghostRGB), ghostAmt);

  let display = aces(max(finalRGB, vec3<f32>(0.0)) * 1.6);
  // Alpha = ink laid down: bare paper is translucent, dense overprint opaque.
  let ink = clamp((outC + outM + outY) * 0.3 + outK * 0.6, 0.0, 1.0);
  let alpha = clamp(0.45 + ink * 0.5 + click * 0.05, 0.0, 1.0);
  let persist = mix(coverage, prev, 0.12 + held * influence * 0.2);
  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  textureStore(writeTexture, pixel, vec4<f32>(display, alpha));
  textureStore(dataTextureA, pixel, persist);
  textureStore(writeDepthTexture, pixel, vec4<f32>(clamp(depth + click * 0.05, 0.0, 1.0), 0.0, 0.0, 0.0));
}
