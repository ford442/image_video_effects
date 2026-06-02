// ═══════════════════════════════════════════════════════════════════
//  Frosty Window v2
//  Category: artistic
//  Features: upgraded-rgba, depth-aware, interactive, persistence, audio-reactive, temporal
//  Complexity: High
//  Upgraded: 2026-05-30
//  By: 4-Agent Upgrade Swarm
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
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn h2(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn voro(p: vec2<f32>) -> vec2<f32> {
  var d = vec2<f32>(1e3, 1e3);
  let i = floor(p);
  for(var y: i32 = -1; y <= 1; y = y + 1) {
    for(var x: i32 = -1; x <= 1; x = x + 1) {
      let n = vec2<f32>(f32(x), f32(y));
      let o = n + vec2<f32>(cos(h2(i + n) * 6.28), sin(h2(i + n) * 6.28)) * 0.45;
      let dist = length(p - i - o);
      if(dist < d.x) { d.y = d.x; d.x = dist; }
      else { d.y = min(d.y, dist); }
    }
  }
  return d;
}

fn fbm(p: vec2<f32>) -> f32 {
  var v = 0.0; var a = 0.5;
  var pp = p;
  let rot = mat2x2<f32>(0.8, 0.6, -0.6, 0.8);
  for(var i: i32 = 0; i < 5; i = i + 1) {
    v = v + a * h2(pp);
    pp = rot * pp * 2.03 + vec2<f32>(1.7, 9.2);
    a = a * 0.5;
  }
  return v;
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp(x * (x * 2.51 + 0.03) / (x * (x * 2.43 + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn dend(p: vec2<f32>, b: i32) -> f32 {
  let a = atan2(p.y, p.x);
  let s = 6.283 / f32(b);
  let sa = fract(a / s + 0.5) - 0.5;
  return length(p) / (abs(sa) + 0.3);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / res;
  let t = u.config.x;
  let bass = plasmaBuffer[0].x;
  let treble = plasmaBuffer[0].z;
  let freeze = max(0.002 + u.zoom_params.x * 0.04 + bass * 0.008, 0.0);
  let scale = mix(8.0, 40.0, u.zoom_params.y);
  let warpAmp = u.zoom_params.z * 0.8;
  let heatR = max(0.04 + u.zoom_params.w * 0.18, 0.001);
  var prev = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
  var frost = prev.r;
  if(frost < 0.005) {
    let base = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeTexture, coord, vec4<f32>(base.rgb, base.a * 0.1));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(0.0, 0.0, 0.0, 0.0));
    return;
  }
  frost = clamp(frost + freeze, 0.0, 1.0);
  let mouse = u.zoom_config.yz;
  let md = distance(uv, mouse);
  let d = 1.0 / max(res.x, res.y);
  let n = textureSampleLevel(dataTextureC, non_filtering_sampler, uv + vec2<f32>(0.0, d), 0.0).r;
  let s = textureSampleLevel(dataTextureC, non_filtering_sampler, uv + vec2<f32>(0.0, -d), 0.0).r;
  let e = textureSampleLevel(dataTextureC, non_filtering_sampler, uv + vec2<f32>(d, 0.0), 0.0).r;
  let w = textureSampleLevel(dataTextureC, non_filtering_sampler, uv + vec2<f32>(-d, 0.0), 0.0).r;
  let lap = (n + s + e + w) * 0.25 - frost;
  let heat = smoothstep(heatR, heatR * 0.2, md);
  frost = frost * (1.0 - heat * 0.9) - lap * heat * 2.0;
  let wv = fbm(uv * scale * 0.3 + vec2<f32>(t * 0.02, 0.0));
  let vp = uv * scale + wv * warpAmp;
  let vd = voro(vp);
  let facet = smoothstep(0.02, 0.08, vd.y - vd.x);
  let dn = dend((uv - 0.5) * scale * 0.5, 6);
  let branch = smoothstep(0.15, 0.35, fract(dn + wv * 0.4));
  var crystal = mix(facet, branch, 0.5);
  crystal = max(crystal, h2(floor(vp * 0.5)) * bass * 0.35 * frost);
  let baseCol = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let off = (crystal * 0.012 + frost * 0.008) * (1.0 + wv);
  let bUV = uv + vec2<f32>(cos(wv * 6.28), sin(wv * 6.28)) * off;
  let blurCol = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).rgb;
  let rUV = uv + vec2<f32>(cos(dn * 2.0 + t), sin(dn * 2.0 + t)) * frost * 0.015;
  let refractCol = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).rgb;
  let thick = frost * (0.6 + crystal * 0.4);
  let sss = vec3<f32>(0.75, 0.88, 1.0) * thick * thick * 0.35;
  let temp = mix(vec3<f32>(0.45, 0.65, 0.92), vec3<f32>(0.95, 0.97, 1.0), thick);
  let fCol = mix(mix(blurCol, refractCol, crystal * 0.3), temp, thick * 0.45) + sss;
  let caust = pow(crystal, 3.0) * frost;
  let rainbow = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.09, 4.18) + fract(dn * 3.0 + t * 0.1) * 6.28);
  let caustic = rainbow * caust * 0.25;
  let sparkle = step(0.92, h2(vp * 100.0 + t)) * treble * crystal * frost * 0.6;
  var col = mix(baseCol, fCol + caustic + sparkle, frost * 0.85);
  col = aces(col * 1.2);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = mix(luma * 0.15, 0.75 + crystal * 0.25 + caust * 0.35, frost);
  let finalAlpha = mix(alpha * 0.7, min(alpha * 1.15, 1.0), depth);
  textureStore(writeTexture, coord, vec4<f32>(col, finalAlpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, vec4<f32>(frost, crystal, caust, finalAlpha));
}
