// ═══════════════════════════════════════════════════════════════════
//  Neon Stellated Octahedron
//  Category: generative
//  Features: star-tetrahedron (stellated octahedron), neon edge glow,
//            dual-tetra rainbow facets, kaleidoscopic symmetry, audio pulse
//  Complexity: High
//  Upgraded: 2026-09-09
//  Ideas: intersection ridge of the two tetras; face vs edge spectral split
//  A packing: ACES display RGBA (HEAD telemetry packing lie fixed)
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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn neon(t: f32, intensity: f32) -> vec3<f32> {
  let base = 0.5 + 0.5 * cos(TAU * (t + vec3<f32>(0.0, 0.33, 0.67)));
  return base * (1.0 + intensity * 2.0);
}

fn rotY(v: vec3<f32>, a: f32) -> vec3<f32> {
  let c = cos(a); let s = sin(a);
  return vec3<f32>(c * v.x + s * v.z, v.y, -s * v.x + c * v.z);
}

fn rotX(v: vec3<f32>, a: f32) -> vec3<f32> {
  let c = cos(a); let s = sin(a);
  return vec3<f32>(v.x, c * v.y - s * v.z, s * v.y + c * v.z);
}

fn sdPlane(p: vec3<f32>, n: vec3<f32>, h: f32) -> f32 {
  return dot(p, n) + h;
}

fn sdSegment3(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>) -> f32 {
  let pa = p - a; let ba = b - a;
  let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
  return length(pa - ba * h);
}

// Regular tetrahedron vertices
fn tetraVerts(s: f32) -> array<vec3<f32>, 4> {
  return array<vec3<f32>, 4>(
    vec3<f32>(1.0, 1.0, 1.0) * s,
    vec3<f32>(1.0, -1.0, -1.0) * s,
    vec3<f32>(-1.0, 1.0, -1.0) * s,
    vec3<f32>(-1.0, -1.0, 1.0) * s
  );
}

fn tetraEdges() -> array<vec2<i32>, 6> {
  return array<vec2<i32>, 6>(
    vec2<i32>(0,1), vec2<i32>(0,2), vec2<i32>(0,3),
    vec2<i32>(1,2), vec2<i32>(1,3), vec2<i32>(2,3)
  );
}

fn stellatedOctaSDF(p: vec3<f32>, scale: f32, edgeThick: f32) -> vec3<f32> {
  let verts = tetraVerts(scale);
  let edges = tetraEdges();
  var e0 = 1e9;
  var e1 = 1e9;
  var minFace = 1e9;

  for (var layer = 0; layer < 2; layer = layer + 1) {
    let flip = select(1.0, -1.0, layer == 1);
    var layerEdge = 1e9;
    for (var i = 0; i < 6; i = i + 1) {
      let e = edges[i];
      let a = verts[e.x] * flip;
      let b = verts[e.y] * flip;
      layerEdge = min(layerEdge, sdSegment3(p, a, b) - edgeThick);
    }
    if (layer == 0) {
      e0 = layerEdge;
    } else {
      e1 = layerEdge;
    }
    let f0 = sdPlane(p, normalize(vec3<f32>(1.0, 1.0, 1.0)), -scale * 0.577 * flip);
    let f1 = sdPlane(p, normalize(vec3<f32>(-1.0, 1.0, 1.0)), -scale * 0.577 * flip);
    minFace = min(minFace, abs(f0));
    minFace = min(minFace, abs(f1));
  }
  let ridge = max(e0, e1);
  return vec3<f32>(min(e0, e1), minFace, ridge);
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

  let starScale = mix(0.4, 0.9, u.zoom_params.x) * (1.0 + bass * 0.12);
  let spin = time * mix(0.1, 0.5, u.zoom_params.y);
  let neonPower = mix(0.5, 2.0, u.zoom_params.z);
  let colorShift = u.zoom_params.w;

  let aspect = res.x / max(res.y, 1.0);
  var p = vec3<f32>((uv01 - 0.5) * vec2<f32>(aspect, 1.0) * 2.2, 1.5);
  let yaw = (mouse.x - 0.5) * TAU + spin;
  let pitch = (mouse.y - 0.5) * PI * 0.6 + sin(time * 0.3) * 0.1;
  p = rotY(rotX(p, pitch), yaw);

  // Kaleidoscopic 6-fold symmetry in XY
  let ang = atan2(p.y, p.x);
  let seg = TAU / 6.0;
  let ka = abs(fract(ang / seg + 0.5) - 0.5) * seg;
  let r = length(p.xy);
  p = vec3<f32>(cos(ka) * r, sin(ka) * r, p.z);

  let edgeThick = mix(0.006, 0.02, u.zoom_params.z);
  let sd = stellatedOctaSDF(p, starScale, edgeThick);
  let edge = exp(-abs(sd.x) * 90.0);
  let facet = exp(-sd.y * 15.0) * 0.35 * (1.0 - edge);
  let ridge = exp(-abs(sd.z) * 70.0);

  let hue = fract(atan2(p.z, p.x) / TAU + length(p) * 0.4 + colorShift + time * 0.06);
  let hue2 = fract(hue + 0.5 + mids * 0.1);

  var color = vec3<f32>(0.01, 0.005, 0.03);
  color += neon(hue, neonPower * edge) * edge * (1.0 + bass * 0.5);
  color += neon(hue2, neonPower * facet) * facet * (0.8 + treble * 0.4);
  color += neon(hue + 0.12, neonPower) * ridge * 0.85 * (0.7 + bass * 0.4);

  // Stellate spike glow at vertices
  let spike = exp(-length(p) * 2.5) * neon(hue + 0.33, 0.8) * 0.3;
  color += spike * (1.0 + treble * 0.5);

  let prev = textureLoad(dataTextureC, pixel, 0);
  color = mix(color, prev.rgb, 0.04);

  let alpha = clamp(edge * 0.9 + facet * 0.4 + length(spike) * 0.3 + ridge * 0.25, 0.0, 1.0);
  let depthOut = clamp(edge * 0.6 + facet * 0.4 + ridge * 0.2, 0.0, 1.0);
  textureStore(dataTextureA, pixel, vec4<f32>(color, alpha));
  color = acesToneMap(color * (1.2 + mids * 0.1));

  textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depthOut, 0.0, 0.0, 1.0));
}
