// ═══════════════════════════════════════════════════════════════════
//  Concentric Spin
//  Category: image
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-09
//  Ideas: exact-C lag; ring-gap tangent conveyor
//  A packing: lag.xy telemetry
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

fn h2(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn fbm(p: vec2<f32>) -> f32 {
  var v = 0.0; var a = 0.5;
  var pp = p;
  let rot = mat2x2<f32>(0.8, 0.6, -0.6, 0.8);
  for(var i: i32 = 0; i < 4; i = i + 1) {
    v = v + a * h2(pp);
    pp = rot * pp * 2.03 + vec2<f32>(1.7, 9.2);
    a = a * 0.5;
  }
  return v;
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp(x * (x * 2.51 + 0.03) / (x * (x * 2.43 + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn rose(r: f32, a: f32, k: f32, n: f32) -> f32 {
  return r * (1.0 + k * cos(a * n));
}

fn epi(r: f32, a: f32, R: f32, rr: f32) -> f32 {
  return length(vec2<f32>(R * cos(a) + rr * cos(a * R / rr), R * sin(a) + rr * sin(a * R / rr))) * r / R;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  if(global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / res;
  let aspect = res.x / max(res.y, 0.001);
  let t = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let density = mix(4.0, 40.0, u.zoom_params.x);
  let speed = mix(0.0, 4.0, u.zoom_params.y) * (1.0 + bass * 0.6);
  let smoothW = u.zoom_params.z * 0.12;
  let gapFade = u.zoom_params.w;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let parallax = (depth - 0.5) * 0.05;
  let targetPos = u.zoom_config.yz * vec2<f32>(aspect, 1.0);
  // Idea 1 — exact-C lag (HEAD used a filtering sample)
  let prevLag = textureLoad(dataTextureC, coord, 0).rg;
  let lag = mix(select(targetPos, prevLag, t > 0.1), targetPos, 0.08);
  let center = lag + vec2<f32>(parallax, parallax);
  let p = uv * vec2<f32>(aspect, 1.0) - center;
  let r = length(p);
  let a = atan2(p.y, p.x);
  let turb = fbm(vec2<f32>(r * 8.0, a * 2.0) + t * 0.15) * 0.25;
  let ringVal = r * density;
  let roseVal = rose(r, a + t * 0.1, 0.25, 5.0) * density;
  let epiVal = epi(r, a + t * 0.05, 3.0, 1.0) * density * 0.5;
  let m0 = smoothstep(0.3, 0.7, mids);
  let m1 = smoothstep(0.7, 1.0, mids);
  let rv = mix(mix(ringVal, roseVal, m0), epiVal, m1) + turb;
  let ri = floor(rv);
  let dir = (ri % 2.0) * 2.0 - 1.0;
  let rot = t * speed * dir;
  let rp = fract(rv);
  let edge = min(rp, 1.0 - rp);
  let gapMask = smoothstep(0.0, smoothW + 0.001, edge);

  // Idea 2 — gap conveyor: slide the photo along the ring tangent in the gap
  let tangent = vec2<f32>(-p.y, p.x) / max(r, 0.001);
  let conveyor = (1.0 - gapMask) * 0.04 * speed;
  let convShift = vec2<f32>(tangent.x / aspect, tangent.y) * conveyor;

  let chroma = 0.025 * (1.0 + treble * 0.5);
  let irid = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.09, 4.18) + (ri * 0.7 + edge * 20.0 + a) * 2.0);
  let rOff = rot + chroma * ri;
  let gOff = rot;
  let bOff = rot - chroma * ri;
  let rP = vec2<f32>(cos(a + rOff), sin(a + rOff)) * r;
  let gP = vec2<f32>(cos(a + gOff), sin(a + gOff)) * r;
  let bP = vec2<f32>(cos(a + bOff), sin(a + bOff)) * r;
  let rUV = clamp((rP + center) / vec2<f32>(aspect, 1.0) + convShift, vec2<f32>(0.0), vec2<f32>(1.0));
  let gUV = clamp((gP + center) / vec2<f32>(aspect, 1.0) + convShift, vec2<f32>(0.0), vec2<f32>(1.0));
  let bUV = clamp((bP + center) / vec2<f32>(aspect, 1.0) + convShift, vec2<f32>(0.0), vec2<f32>(1.0));
  let rCol = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
  let gCol = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
  let bCol = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
  let srcA = textureSampleLevel(readTexture, u_sampler, uv, 0.0).a;
  var pulse = 0.0;
  let rc = u32(u.config.y);
  for(var i: u32 = 0u; i < min(rc, 10u); i = i + 1u) {
    let rip = u.ripples[i];
    let rd = distance(uv, rip.xy);
    let age = t - rip.z;
    pulse = pulse + exp(-age * 3.0) * smoothstep(0.05, 0.0, abs(rd - age * 0.3)) * treble;
  }
  let bloom = pow(gapMask * (1.0 - gapMask) * 4.0, 2.0) * (1.0 + bass * 0.5);
  var col = vec3<f32>(rCol, gCol, bCol);
  col = col + irid * bloom * 0.35;
  col = col + vec3<f32>(pulse) * 0.4;
  col = aces(col * (1.0 + bass * 0.15));
  let sheen = pow(abs(cos(a * 3.0 + rot)), 4.0) * bass * 0.2 * gapMask;
  col = col + vec3<f32>(sheen);
  let alpha = clamp(gapMask * (1.0 - gapFade * 0.5) + bloom * 0.3 + pulse * 0.5 + srcA * 0.15, 0.0, 1.0);
  textureStore(writeTexture, coord, vec4<f32>(col, alpha));
  textureStore(dataTextureA, coord, vec4<f32>(lag, 0.0, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
