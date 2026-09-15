// ═══════════════════════════════════════════════════════════════════
//  RGB Diffraction
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-15
//  Ideas: blazed grating (asymmetric +1 order); spectral order ghosts at m=±1
//  A packing: ACES display RGBA
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
  config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // x=Evolution Speed, y=Fringe Frequency, z=Chromatic Spread, w=Brightness
  ripples: array<vec4<f32>, 50>,
};

const TAU: f32 = 6.283185307179586;
const SLITS: i32 = 6;
const SYMMETRY: i32 = 6;

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
  let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  let p = abs(fract(c.xxx + k.xyz) * 6.0 - k.www);
  return c.z * mix(k.xxx, clamp(p - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn applySymmetry(q: vec2<f32>, k: i32) -> vec2<f32> {
  let sectors = f32(k);
  let angle   = atan2(q.y, q.x);
  let r       = length(q);
  let secAngle = TAU / sectors;
  let sector   = floor(angle / secAngle);
  let localA   = angle - sector * secAngle;
  let foldA = select(localA, secAngle - localA, localA > secAngle * 0.5);
  return vec2<f32>(cos(foldA), sin(foldA)) * r;
}

// Diffraction from a single slit. Idea 1: blaze tilts the sinc envelope
// along the grating axis so the +1 order outshines −1.
fn slitIntensity(p: vec2<f32>, slitPos: f32, axisDir: vec2<f32>, freq: f32, phase: f32, lambda: f32, blaze: f32) -> f32 {
  let proj   = dot(p, axisDir) - slitPos;
  let wave   = 0.5 + 0.5 * cos(proj * freq * TAU + phase);
  let dist   = abs(dot(p, vec2<f32>(-axisDir.y, axisDir.x)));
  let envArg = dist * freq * 0.5 * lambda;
  let sinc   = select(1.0, sin(envArg) / envArg, abs(envArg) > 0.001);
  let blazeEnv = clamp(1.0 + blaze * proj, 0.15, 2.2);
  return wave * sinc * sinc * blazeEnv;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res    = u.config.zw;
  if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

  let coord  = vec2<i32>(global_id.xy);
  let dims   = textureDimensions(dataTextureC);
  let uv     = vec2<f32>(global_id.xy) / res;
  let time   = u.config.x;
  let aspect = res.x / max(res.y, 1.0);
  let bass   = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids   = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

  let speed    = mix(0.2,  2.5, u.zoom_params.x);
  let freq     = mix(4.0, 22.0, u.zoom_params.y);
  let chromAb  = mix(0.8,  2.2, u.zoom_params.z);
  let brightness = mix(0.6, 2.0, u.zoom_params.w);

  var p = (uv - 0.5) * vec2<f32>(aspect, 1.0) * 2.0;
  // Pointer tilts the grating (viewing angle), identity unchanged when mouse is centered.
  let tilt = (u.zoom_config.yz - vec2<f32>(0.5)) * select(0.55, 1.15, u.zoom_config.w > 0.5);
  p = p - tilt * 0.35;
  p = applySymmetry(p, SYMMETRY);

  // Click ripples kick optical path (phase), not a spring mass.
  var phaseKick = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
    let rp = u.ripples[ri];
    let age = time - rp.z;
    if (age < 0.0 || age > 3.0) { continue; }
    let delta = (uv - rp.xy) * vec2<f32>(aspect, 1.0);
    let dist = length(delta);
    let envelope = exp(-dist * 6.0) * exp(-age * 1.2);
    phaseKick = phaseKick + sin(dist * 48.0 - age * 10.0) * envelope * TAU * 0.35;
  }

  let lambdaR = 1.0 * chromAb;
  let lambdaG = 0.82 * chromAb;
  let lambdaB = 0.68 * chromAb;
  let blaze = 0.55 + bass * 0.35;

  var r = 0.0;
  var g = 0.0;
  var b = 0.0;

  let chromOffsetR = vec2<f32>(bass * 0.02, 0.0);
  let chromOffsetG = vec2<f32>(0.0, mids * 0.02);
  let chromOffsetB = vec2<f32>(-treble * 0.02, treble * 0.02);

  for (var si: i32 = 0; si < SLITS; si = si + 1) {
    let sf      = f32(si);
    let slitAngle = sf / f32(SLITS) * TAU + time * speed * 0.05;
    let axis    = vec2<f32>(cos(slitAngle), sin(slitAngle));
    let slitPos = (sf - f32(SLITS) * 0.5) * 0.18;
    let phase   = time * speed * (0.6 + sf * 0.23) + bass * TAU * 0.4 + phaseKick;

    r = r + slitIntensity(p + chromOffsetR, slitPos, axis, freq * lambdaR, phase, lambdaR, blaze);
    g = g + slitIntensity(p + chromOffsetG, slitPos, axis, freq * lambdaG, phase + 0.3, lambdaG, blaze);
    b = b + slitIntensity(p + chromOffsetB, slitPos, axis, freq * lambdaB, phase + 0.6, lambdaB, blaze);

    // Idea 2 — spectral order ghosts at m=±1 (2× spatial frequency, same slits).
    let ghost = 0.28 + treble * 0.12;
    r = r + ghost * slitIntensity(p + chromOffsetR, slitPos, axis, freq * lambdaR * 2.0, phase, lambdaR, blaze * 0.65);
    g = g + ghost * slitIntensity(p + chromOffsetG, slitPos, axis, freq * lambdaG * 2.0, phase + 0.3, lambdaG, blaze * 0.65);
    b = b + ghost * slitIntensity(p + chromOffsetB, slitPos, axis, freq * lambdaB * 2.0, phase + 0.6, lambdaB, blaze * 0.65);
  }

  let norm    = 1.0 / max(f32(SLITS) * 0.6, 1.0);
  var color   = vec3<f32>(r, g, b) * norm * brightness * (1.0 + mids * 0.4);

  let shimHue = fract(time * speed * 0.04 + treble * 0.2);
  let shimRgb = hsv2rgb(vec3<f32>(shimHue, 0.4, 1.0));
  color = color + shimRgb * 0.08;

  let vign  = 1.0 - smoothstep(0.6, 1.2, length(p * 0.5));
  color = color * vign;

  let prevCoord = clamp(coord, vec2<i32>(0), vec2<i32>(dims) - vec2<i32>(1));
  let prev = textureLoad(dataTextureC, prevCoord, 0);
  color = mix(color, prev.rgb * 0.9, 0.03 + bass * 0.01);

  color = acesToneMap(color);

  let depth = clamp((r + g + b) * norm * 0.4, 0.0, 1.0);
  let alpha = clamp(length(color) * 0.6 + abs(phaseKick) * 0.08, 0.0, 1.0);
  let outCol = vec4<f32>(color, alpha);

  textureStore(writeTexture,      coord, outCol);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA,      coord, outCol);
}
