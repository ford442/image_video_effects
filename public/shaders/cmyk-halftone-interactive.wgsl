// ================================================================
//  CMYK Halftone Interactive — Batch 56 cursor+main merge
//  Rosette rings, rotating screens, registration drift/shear,
//  ink conveyors/packets, click blooms, rainbow registration glow.
//  A remains CMYK coverage masks.
// ================================================================

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

fn rgb2cmyk(rgb: vec3<f32>) -> vec4<f32> {
  let k = 1.0 - max(rgb.r, max(rgb.g, rgb.b));
  let denom = max(1.0 - k, 0.0001);
  let c = (1.0 - rgb.r - k) / denom;
  let m = (1.0 - rgb.g - k) / denom;
  let y = (1.0 - rgb.b - k) / denom;
  return select(vec4<f32>(c, m, y, k), vec4<f32>(0.0, 0.0, 0.0, 1.0), k >= 0.999);
}

fn rotate(v: vec2<f32>, a: f32) -> vec2<f32> {
  let s = sin(a);
  let c = cos(a);
  return vec2<f32>(v.x * c - v.y * s, v.x * s + v.y * c);
}

fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
  let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  let p = abs(fract(hsv.xxx + k.xyz) * 6.0 - k.www);
  return hsv.z * mix(k.xxx, clamp(p - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), hsv.y);
}

fn halftone_dot(
  uv: vec2<f32>,
  aspect: f32,
  density: f32,
  angle: f32,
  offset: vec2<f32>,
  amount: f32,
  radiusScale: f32
) -> f32 {
  let localUV = rotate((uv + offset) * vec2<f32>(aspect, 1.0), angle) * density;
  let grid = fract(localUV) - 0.5;
  let dist = length(grid);
  let radius = clamp(sqrt(clamp(amount, 0.0, 1.0)) * 0.6 * radiusScale, 0.0, 0.75);
  let disc = 1.0 - smoothstep(radius - 0.05, radius + 0.05, dist);
  let ring = 1.0 - smoothstep(0.03, 0.08, abs(dist - radius * 0.72));
  return max(disc, ring * 0.35);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let mouse = u.zoom_config.yz;
  let time = u.config.x;
  let mouseDown = u.zoom_config.w > 0.5;
  let held = f32(mouseDown);
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
  let prev = textureLoad(dataTextureC, pixel, 0);

  let density = 40.0 + u.zoom_params.x * 170.0;
  let baseAngle = u.zoom_params.y * 3.14159 + time * (0.08 + audio.y * 0.12);
  let spread = u.zoom_params.z * 0.05;
  let inkDarkness = 0.5 + u.zoom_params.w * 0.5;

  let drift = vec2<f32>(sin(time * 0.73), cos(time * 0.91)) * (0.002 + 0.006 * audio.xy);
  let heldDelta = (uv - mouse) * select(0.0, 1.0, mouseDown);
  let interactAngle = (mouse.x - 0.5) * 3.14159 * (1.0 + held * 0.45) + heldDelta.y * 1.4;
  let finalSpread = spread + mouse.y * 0.10;

  let srcColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let cmyk = rgb2cmyk(srcColor);

  let angC = radians(15.0) + baseAngle + interactAngle;
  let angM = radians(75.0) + baseAngle + interactAngle;
  let angY = radians(0.0) + baseAngle + interactAngle;
  let angK = radians(45.0) + baseAngle + interactAngle;

  var bloom = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let event = u.ripples[i];
    let age = max(time - event.z, 0.0);
    let radius = length((uv - event.xy) * vec2<f32>(aspect, 1.0));
    bloom += exp(-age * 1.7) * exp(-abs(radius - age * 0.32) * 70.0);
  }

  let shear = vec2<f32>(heldDelta.y, heldDelta.x) * 0.025;
  let offC = vec2<f32>(-1.0, 0.0) * finalSpread * (1.0 + audio.x * 0.4) + drift + shear;
  let offM = vec2<f32>(1.0, 0.0) * finalSpread * (1.0 + audio.y * 0.4) - drift - shear;
  let offY = vec2<f32>(0.0, -1.0) * finalSpread * (1.0 + audio.z * 0.4) + drift.yx;
  let offK = vec2<f32>(0.0, 1.0) * finalSpread * (1.0 + (audio.x + audio.y) * 0.2) - drift.yx;

  let finalC = halftone_dot(uv, aspect, density, angC, offC, cmyk.x, 1.0 + audio.x * 0.35);
  let finalM = halftone_dot(uv, aspect, density, angM, offM, cmyk.y, 1.0 + audio.y * 0.35);
  let finalY = halftone_dot(uv, aspect, density, angY, offY, cmyk.z, 1.0 + audio.z * 0.35);
  let finalK = halftone_dot(uv, aspect, density, angK, offK, cmyk.w, 1.0 + (audio.x + audio.z) * 0.20);

  let mixC = mix(vec3<f32>(1.0), vec3<f32>(0.0, 1.0, 1.0), finalC * inkDarkness);
  let mixM = mix(vec3<f32>(1.0), vec3<f32>(1.0, 0.0, 1.0), finalM * inkDarkness);
  let mixY = mix(vec3<f32>(1.0), vec3<f32>(1.0, 1.0, 0.0), finalY * inkDarkness);
  let mixK = mix(vec3<f32>(1.0), vec3<f32>(0.0, 0.0, 0.0), finalK * inkDarkness);

  let conveyor = smoothstep(0.1, 0.0, abs(fract(uv.x * density * 0.04 - time * (1.6 + audio.x * 2.0)) - 0.5));
  let packets = smoothstep(0.09, 0.0, abs(fract(length((uv - mouse) * vec2<f32>(aspect, 1.0)) * 9.0 - time * 2.6) - 0.5));
  let coverage = clamp((finalC + finalM + finalY + finalK) * 0.25, 0.0, 1.0);
  let hue = fract(coverage + time * 0.08 + audio.y * 0.2);
  let slick = hsv2rgb(vec3<f32>(hue, 0.55, 1.0));
  let paperTint = mix(vec3<f32>(1.0), vec3<f32>(0.98, 0.95, 0.90), inkDarkness * 0.25);
  let registrationGlow =
    vec3<f32>(finalC, finalM, finalY) * vec3<f32>(0.05 + 0.08 * audio.x, 0.04 + 0.08 * audio.y, 0.03 + 0.08 * audio.z);
  let rosette = 0.5 + 0.5 * sin(length((uv - 0.5) * vec2<f32>(aspect, 1.0)) * density * 5.0 - time * 1.4);
  let spectralBloom = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.094, 4.188) + bloom * 5.0 + time);

  var finalColor = paperTint * mixC * mixM * mixY * mixK;
  finalColor = mix(finalColor, finalColor * slick * 1.2, 0.22 + audio.z * 0.18);
  finalColor += slick * (conveyor * 0.14 + packets * 0.18 + bloom * 0.22) * (0.4 + held * 0.2);
  finalColor += registrationGlow + spectralBloom * bloom * 0.22 + rosette * finalC * finalM * 0.05;

  let finalAlpha = clamp(0.58 + coverage * 0.38 + cmyk.w * 0.10 + bloom * 0.06, 0.50, 0.98);
  let baseDepth = textureLoad(readDepthTexture, pixel, 0).r;
  let depthOut = clamp(mix(baseDepth, 0.25 + coverage * 0.70, 0.25) + bloom * 0.04, 0.0, 1.0);
  let cmykOut = vec4<f32>(finalC, finalM, finalY, finalK);
  let persist = mix(cmykOut, prev, 0.18);

  textureStore(writeTexture, pixel, vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  // A remains CMYK coverage (with light temporal persistence).
  textureStore(dataTextureA, pixel, persist);
}
