// ═══════════════════════════════════════════════════════════════════
//  Hypnotic Vortex Tunnel
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba,
//            hdr-aces, oklab-mix, blackbody-temperature,
//            atmospheric-fog, fresnel-rim, volumetric-glow
//  Complexity: Medium
//  Created: 2026-05-30
//  Upgraded: 2026-07-13
//  An infinite tunnel of nested vortex rings coloured by
//  spectral light — bass drives rotation, treble adds strobe arcs.
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Rings, y=RotSpeed, z=Zoom, w=Distort
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn huePreservingClamp(col: vec3<f32>, maxVal: f32) -> vec3<f32> {
    let mx = max(max(col.r, col.g), col.b);
    let scale = min(mx, maxVal) / max(mx, 0.0001);
    return col * scale;
}

fn rgbToOkLab(c: vec3<f32>) -> vec3<f32> {
    let lms = mat3x3<f32>(
        0.8189330101, 0.3618667424, -0.1288597137,
        0.0329845436, 0.9293118715, 0.0361456387,
        0.0482003018, 0.2643662691, 0.6338517070
    ) * c;
    let lms_ = sign(lms) * pow(abs(lms), vec3<f32>(1.0 / 3.0));
    return mat3x3<f32>(
        0.2104542553, 0.7936177850, -0.0040720468,
        1.9779984951, -2.4285922050, 0.4505937099,
        0.0259040371, 0.7827717662, -0.8086757660
    ) * lms_;
}

fn okLabToRgb(c: vec3<f32>) -> vec3<f32> {
    let lms_ = mat3x3<f32>(
        1.0, 0.3963377774, 0.2158037573,
        1.0, -0.1055613458, -0.0638541728,
        1.0, -0.0894841775, -1.2914855480
    ) * c;
    let lms = lms_ * lms_ * lms_;
    return mat3x3<f32>(
        4.0767416621, -3.3077115913, 0.2309699292,
        -1.2684380046, 2.6097574011, -0.3413193965,
        -0.0041960863, -0.7034186147, 1.7076147010
    ) * lms;
}

fn blackbody(t: f32) -> vec3<f32> {
    let T = mix(1800.0, 14000.0, clamp(t, 0.0, 1.0));
    let g = clamp(0.0001 * T - 0.05, 0.0, 1.0);
    let b = clamp(0.00004 * (T - 4200.0), 0.0, 1.0);
    return vec3<f32>(1.0, g, b) * (T / 5000.0);
}

fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y
    );
}

fn fbm(p: vec2<f32>, oct: i32) -> f32 {
    var s = 0.0; var a = 0.5; var f = 1.0;
    for (var i = 0; i < oct; i++) { s += a * valueNoise(p * f); f *= 2.0; a *= 0.5; }
    return s;
}

fn tunnelLayer(
  r: f32, theta: f32, z: f32,
  t: f32, bass: f32, mids: f32, treble: f32,
  rotSpeed: f32, distort: f32
) -> vec3<f32> {
  let spin = theta + t * rotSpeed * (1.0 + bass * 0.5) + z * 0.3;

  let ringMask = sin(r * 30.0 - t * (2.0 + bass * 1.5)) * 0.5 + 0.5;
  let spokeMask = sin(spin * 8.0 + z * 0.5) * 0.5 + 0.5;
  let combined = ringMask * spokeMask;

  let hue = fract(z * 0.15 + theta * 0.16 + t * 0.05 + mids * 0.1);
  let col = vec3<f32>(
    0.5 + 0.5 * cos(TAU * hue),
    0.5 + 0.5 * cos(TAU * (hue + 0.33)),
    0.5 + 0.5 * cos(TAU * (hue + 0.67))
  );

  let arcAngle = fract(spin / TAU);
  let arc = smoothstep(0.04, 0.0, abs(arcAngle - 0.5)) * treble * 0.5;

  let warp = distort * 0.15 * sin(r * 10.0 + t * 3.0 + mids * 2.0);
  return col * (combined + arc) * (1.0 + warp);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }
  let coord = vec2<i32>(gid.xy);
  let uv = vec2<f32>(gid.xy) / vec2<f32>(dims);
  let t = u.config.x;

  let bass   = plasmaBuffer[0].x;
  let mids   = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let nRings   = mix(4.0, 16.0, u.zoom_params.x);
  let rotSpeed = mix(0.2, 2.0, u.zoom_params.y);
  let zoom     = mix(0.5, 2.5, u.zoom_params.z) * (1.0 + bass * 0.2);
  let distort  = u.zoom_params.w;

  let mouse = u.zoom_config.yz * 2.0 - 1.0;
  let aspect = u.config.z / max(u.config.w, 1.0);
  var p = (uv * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);
  let vp = mouse * 0.4 * u.zoom_config.w;
  let pv = p - vp;

  let r = length(pv);
  let theta = atan2(pv.y, pv.x);

  let zBase = -log(max(r / zoom, 0.001)) + t * 0.5 * (1.0 + bass * 0.2);

  var col = vec3<f32>(0.0);
  let layers = i32(nRings);
  for (var i = 0; i < layers; i++) {
    let z = zBase + f32(i) * (TAU / nRings);
    col += tunnelLayer(r, theta, z, t, bass, mids, treble, rotSpeed, distort);
  }
  col /= f32(layers);

  let depthFactor = clamp(1.0 - r / zoom, 0.0, 1.0);
  let fog = exp(-r * (1.2 + bass * 0.3)) * (0.7 + treble * 0.3);
  let fogCol = blackbody(0.25 + mids * 0.15) * fog;
  col = col + fogCol;

  let fresnel = pow(1.0 - abs(dot(normalize(vec3<f32>(pv, 0.1)), vec3<f32>(0.0, 0.0, 1.0))), 3.0);
  let rim = vec3<f32>(0.6, 0.85, 1.0) * fresnel * (1.0 + treble) * depthFactor;
  col = col + rim;

  let iris = 1.0 - smoothstep(0.0, 0.06, r);
  col = mix(col, vec3<f32>(0.0), iris);

  col *= 1.0 - smoothstep(0.8 * zoom, 1.4 * zoom, r);

  let prev = textureLoad(dataTextureC, coord, 0).rgb;
  let okPrev = rgbToOkLab(prev * 0.96);
  let okCol = rgbToOkLab(col);
  let okMix = mix(okPrev, okCol, 0.35 + bass * 0.1);
  col = okLabToRgb(okMix);

  col = huePreservingClamp(col, 6.0);
  col = acesToneMap(col * 1.25);

  let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp(luma + (1.0 - iris) * 0.05 + fog * 0.2, 0.0, 1.0);
  let depth = clamp(1.0 - r / zoom, 0.0, 1.0);

  let finalColor = vec4<f32>(col, alpha);
  textureStore(writeTexture,      coord, finalColor);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA,      coord, finalColor);
}
