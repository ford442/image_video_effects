// ═══════════════════════════════════════════════════════════════════
//  Rainbow Icosahedron Cascade
//  Category: generative
//  Features: nested icosahedral shells, spectral facet coloring, orbit-trap
//            edges, audio-reactive scale, mouse orbit, temporal feedback
//  Complexity: High
//  Created: 2026-07-12
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
const TAU: f32 = 6.28318530718;
const PHI: f32 = 1.61803398874989484820;

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn spectral(t: f32) -> vec3<f32> {
  return 0.5 + 0.5 * cos(TAU * (t + vec3<f32>(0.0, 0.33, 0.67)));
}

fn rotY(v: vec3<f32>, a: f32) -> vec3<f32> {
  let c = cos(a); let s = sin(a);
  return vec3<f32>(c * v.x + s * v.z, v.y, -s * v.x + c * v.z);
}

fn rotX(v: vec3<f32>, a: f32) -> vec3<f32> {
  let c = cos(a); let s = sin(a);
  return vec3<f32>(v.x, c * v.y - s * v.z, s * v.y + c * v.z);
}

fn sdSegment3(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>) -> f32 {
  let pa = p - a; let ba = b - a;
  let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
  return length(pa - ba * h);
}

// Icosahedron vertices (unit sphere, golden-ratio construction)
fn icosaVerts() -> array<vec3<f32>, 12> {
  let t = PHI;
  return array<vec3<f32>, 12>(
    normalize(vec3<f32>(0.0, 1.0, t)),
    normalize(vec3<f32>(0.0, 1.0, -t)),
    normalize(vec3<f32>(0.0, -1.0, t)),
    normalize(vec3<f32>(0.0, -1.0, -t)),
    normalize(vec3<f32>(1.0, t, 0.0)),
    normalize(vec3<f32>(1.0, -t, 0.0)),
    normalize(vec3<f32>(-1.0, t, 0.0)),
    normalize(vec3<f32>(-1.0, -t, 0.0)),
    normalize(vec3<f32>(t, 0.0, 1.0)),
    normalize(vec3<f32>(-t, 0.0, 1.0)),
    normalize(vec3<f32>(t, 0.0, -1.0)),
    normalize(vec3<f32>(-t, 0.0, -1.0))
  );
}

fn icosaEdges() -> array<vec2<i32>, 30> {
  return array<vec2<i32>, 30>(
    vec2<i32>(0,8), vec2<i32>(0,9), vec2<i32>(0,4), vec2<i32>(0,6),
    vec2<i32>(1,10), vec2<i32>(1,11), vec2<i32>(1,4), vec2<i32>(1,6),
    vec2<i32>(2,8), vec2<i32>(2,9), vec2<i32>(2,5), vec2<i32>(2,7),
    vec2<i32>(3,10), vec2<i32>(3,11), vec2<i32>(3,5), vec2<i32>(3,7),
    vec2<i32>(4,8), vec2<i32>(4,10), vec2<i32>(5,8), vec2<i32>(5,10),
    vec2<i32>(6,9), vec2<i32>(6,11), vec2<i32>(7,9), vec2<i32>(7,11),
    vec2<i32>(8,2), vec2<i32>(9,2), vec2<i32>(10,3), vec2<i32>(11,3),
    vec2<i32>(4,1), vec2<i32>(6,1)
  );
}

fn icosaShellSDF(p: vec3<f32>, scale: f32, thick: f32) -> f32 {
  let verts = icosaVerts();
  let edges = icosaEdges();
  var md = 1e9;
  for (var i = 0; i < 30; i = i + 1) {
    let e = edges[i];
    let a = verts[e.x] * scale;
    let b = verts[e.y] * scale;
    md = min(md, sdSegment3(p, a, b) - thick);
  }
  return md;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let res = vec2<f32>(u.config.zw);
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

  let uv01 = vec2<f32>(pixel) / res;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let mouse = u.zoom_config.yz;

  let shellCount = i32(mix(2.0, 6.0, u.zoom_params.x));
  let shellGap = mix(0.12, 0.35, u.zoom_params.y);
  let edgeGlow = mix(0.004, 0.018, u.zoom_params.z);
  let hueDrift = u.zoom_params.w;

  let aspect = res.x / max(res.y, 1.0);
  var p = vec3<f32>((uv01 - 0.5) * vec2<f32>(aspect, 1.0) * 2.2, 2.8);
  let yaw = (mouse.x - 0.5) * TAU + time * mix(0.08, 0.35, u.zoom_params.y);
  let pitch = (0.5 - mouse.y) * PI * 0.7 + sin(time * 0.25) * 0.15;
  p = rotY(rotX(p, pitch), yaw);

  var color = vec3<f32>(0.02, 0.01, 0.06);
  var alpha = 0.0;
  var minDist = 1e9;
  var facetHue = 0.0;

  let baseScale = 0.55 + bass * 0.15;

  for (var s = 0; s < shellCount; s = s + 1) {
    let sf = f32(s);
    let scale = baseScale + sf * shellGap * (1.0 + mids * 0.2);
    let thick = edgeGlow * (1.0 - sf * 0.08);
    let d = icosaShellSDF(p, scale, thick);
    minDist = min(minDist, d);

    let edge = exp(-abs(d) * 80.0);
    let facet = exp(-max(d, 0.0) * 25.0);
    let hue = fract(sf * 0.17 + hueDrift + time * 0.04 + length(p) * 0.3);
    let spec = spectral(hue + treble * 0.1);

    color += spec * edge * (1.2 + bass * 0.5);
    color += spec * facet * 0.25 * (0.6 + mids * 0.4);
    facetHue = mix(facetHue, hue, edge);
    alpha = max(alpha, edge * (0.7 - sf * 0.08));
  }

  // Inner glow core
  let core = exp(-length(p) * 1.8) * spectral(facetHue + 0.1);
  color += core * (0.4 + treble * 0.3);

  let prev = textureLoad(dataTextureC, pixel, 0);
  color = mix(color, prev.rgb, 0.04 + mids * 0.02);
  color = acesToneMap(color * (1.15 + bass * 0.2));

  alpha = clamp(alpha + length(core) * 0.3, 0.0, 1.0);
  let depthOut = clamp(1.0 - minDist * 3.0, 0.0, 1.0);

  textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depthOut, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, pixel, vec4<f32>(minDist, facetHue, alpha, 1.0));
}
