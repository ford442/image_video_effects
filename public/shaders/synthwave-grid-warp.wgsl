// ═══════════════════════════════════════════════════════════════════
//  Synthwave Grid Warp
//  Category: retro-glitch
//  Features: mouse-driven, audio-reactive
//  Complexity: High
//  Upgraded: 2026-04-25
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

// ── Hash & Noise ─────────────────────────────────────────────
fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}
fn hash11(p: f32) -> f32 {
  return fract(sin(p * 12.9898) * 43758.5453);
}
fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let a = hash21(i);
  let b = hash21(i + vec2<f32>(1.0, 0.0));
  let c = hash21(i + vec2<f32>(0.0, 1.0));
  let d = hash21(i + vec2<f32>(1.0, 1.0));
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var sum = 0.0;
  var amp = 0.5;
  var freq = 1.0;
  for (var i = 0; i < octaves; i = i + 1) {
    sum = sum + amp * valueNoise(p * freq);
    freq = freq * 2.0;
    amp = amp * 0.5;
  }
  return sum;
}
fn rgbToLuma(rgb: vec3<f32>) -> f32 {
  return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}
fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
  let c = hsv.z * hsv.y;
  let h = hsv.x * 6.0;
  let x = c * (1.0 - abs(fract(h) * 2.0 - 1.0));
  var rgb = vec3<f32>(0.0);
  if (h < 1.0)      { rgb = vec3<f32>(c, x, 0.0); }
  else if (h < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
  else if (h < 3.0) { rgb = vec3<f32>(0.0, c, x); }
  else if (h < 4.0) { rgb = vec3<f32>(0.0, x, c); }
  else if (h < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
  else              { rgb = vec3<f32>(c, 0.0, x); }
  return rgb + vec3<f32>(hsv.z - c);
}
fn sdCircle(p: vec2<f32>, r: f32) -> f32 {
  return length(p) - r;
}
fn sdBox(p: vec2<f32>, b: vec2<f32>) -> f32 {
  let d = abs(p) - b;
  return length(max(d, vec2<f32>(0.0))) + min(max(d.x, d.y), 0.0);
}
fn sdLine(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
  let pa = p - a;
  let ba = b - a;
  let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
  return length(pa - ba * h);
}

// ── Screen → World ───────────────────────────────────────────
fn screenToWorld(uv: vec2<f32>, camY: f32, fov: f32) -> vec3<f32> {
  let ndc = (uv - vec2<f32>(0.5)) * 2.0;
  let f = 1.0 / tan(fov * 0.5);
  let t = camY / max(camY - ndc.y * f, 0.001);
  return vec3<f32>(ndc.x * f * t, 0.0, -f * t);
}

// ── Grid SDF ─────────────────────────────────────────────────
fn sdGrid(p: vec3<f32>, spacing: f32) -> f32 {
  let gx = abs(fract(p.x / spacing - 0.5) - 0.5);
  let gz = abs(fract(p.z / spacing - 0.5) - 0.5);
  return min(gx, gz) * spacing;
}

// ── Height Fog ───────────────────────────────────────────────
fn heightFog(dist: f32, height: f32, density: f32, falloff: f32) -> f32 {
  return exp(-density * dist) * exp(-falloff * max(0.0, height));
}

// ── Sun ──────────────────────────────────────────────────────
fn renderSun(uv: vec2<f32>, sunPos: vec2<f32>, size: f32, glow: f32) -> vec3<f32> {
  let d = length(uv - sunPos);
  let core = smoothstep(size, size - 0.001, d);
  let halo = pow(smoothstep(size + glow, size, d), 2.0);
  return vec3<f32>(1.0, 0.9, 0.6) * (core + halo * 0.5);
}

// ── Mountain Layer ───────────────────────────────────────────
fn mountainLayer(uv: vec2<f32>, layerZ: f32, scale: f32, height: f32, sunPos: vec2<f32>) -> vec4<f32> {
  let n = textureSampleLevel(readTexture, u_sampler, vec2<f32>(uv.x * scale, 0.0), 0.0).r;
  let h = n * height;
  let dist = uv.y - h;
  let inside = 1.0 - smoothstep(0.0, 0.02, dist);
  let col = mix(vec3<f32>(0.1, 0.07, 0.2), vec3<f32>(0.3, 0.2, 0.4), inside);
  let toSun = sunPos - uv;
  let rim = max(dot(normalize(vec2<f32>(0.0, 1.0) - vec2<f32>(0.0, h)), normalize(toSun + vec2<f32>(0.0001))), 0.0);
  let col2 = col + rim * 0.2;
  return vec4<f32>(col2, inside);
}

// ── MAIN ─────────────────────────────────────────────────────
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let uv = vec2<f32>(global_id.xy) / resolution;

  let camY = mix(0.5, 3.0, u.zoom_params.x);
  let fogDensity = mix(0.1, 2.0, u.zoom_params.y);
  let fogFalloff = mix(0.0, 1.0, u.zoom_params.z);
  let mountainScale = mix(1.0, 8.0, u.zoom_params.w);
  let time = u.config.x;

  let worldPos = screenToWorld(uv, camY, 1.2);
  let dist = length(worldPos);

  let gridDist = sdGrid(worldPos, 0.5);
  let gridLine = smoothstep(0.02, 0.0, gridDist);
  let gridCol = vec3<f32>(0.0, 0.8, 1.0) * gridLine;

  let fog = heightFog(dist, 0.0, fogDensity, fogFalloff);

  let sunPos = vec2<f32>(0.5 + sin(time * 0.05) * 0.1, 0.3);
  let sun = renderSun(uv, sunPos, 0.05, 0.2);

  let m1 = mountainLayer(uv, 0.2, mountainScale, 0.15, sunPos);
  let m2 = mountainLayer(uv, 0.5, mountainScale * 1.5, 0.09, sunPos);

  var col = gridCol * fog + sun;
  col = mix(col, m1.rgb, m1.a * fog);
  col = mix(col, m2.rgb, m2.a * fog);

  let sunset = mix(vec3<f32>(0.9, 0.4, 0.5), vec3<f32>(0.1, 0.05, 0.2), uv.y);
  col = mix(sunset, col, clamp(gridLine + m1.a + m2.a + length(sun), 0.0, 1.0));

  col = col / (col + vec3<f32>(1.0));

  let alpha = clamp(gridLine * 2.0 + length(sun) + m1.a + m2.a, 0.0, 1.0) * fog;

  textureStore(writeTexture, global_id.xy, vec4<f32>(col, alpha));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
