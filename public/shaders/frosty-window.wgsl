// ═══════════════════════════════════════════════════════════════════
//  Frosty Window v2
//  Category: artistic
//  Features: upgraded-rgba, depth-aware, interactive, persistence, audio-reactive, temporal
//  Complexity: High
//  By: 4-Agent Upgrade Swarm
//  Upgraded: 2026-09-21 (first 2026-05-30)
//  Ideas: frost nucleates on the window frame and creeps inward along the crystal branches;
//         cursor meltwater runs down the glass as clear lensing runnels that hold off refreezing
//  A packing: R frost, G meltwater, B caustic, A alpha
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
  let hi = vec2<i32>(res) - vec2<i32>(1);
  let prev = textureLoad(dataTextureC, coord, 0);
  let cN = textureLoad(dataTextureC, clamp(coord + vec2<i32>(0, 1), vec2<i32>(0), hi), 0);
  let cS = textureLoad(dataTextureC, clamp(coord - vec2<i32>(0, 1), vec2<i32>(0), hi), 0);
  let cE = textureLoad(dataTextureC, clamp(coord + vec2<i32>(1, 0), vec2<i32>(0), hi), 0);
  let cW = textureLoad(dataTextureC, clamp(coord - vec2<i32>(1, 0), vec2<i32>(0), hi), 0);
  var frost = prev.r;

  // Crystal pattern (verbatim math, computed before the growth step so the front can follow it).
  let wv = fbm(uv * scale * 0.3 + vec2<f32>(t * 0.02, 0.0));
  let vp = uv * scale + wv * warpAmp;
  let vd = voro(vp);
  let facet = smoothstep(0.02, 0.08, vd.y - vd.x);
  let dn = dend((uv - 0.5) * scale * 0.5, 6);
  let branch = smoothstep(0.15, 0.35, fract(dn + wv * 0.4));
  var crystal = mix(facet, branch, 0.5);

  // Idea 2 (transport) — meltwater runs down the glass. Each pixel takes water from the pixel
  // above, jogging a pixel sideways per block so the runnels meander; water drains slowly.
  let jog = i32(floor(h2(vec2<f32>(floor(f32(coord.x) / 6.0), floor(f32(coord.y) / 22.0))) * 3.0)) - 1;
  let fromAbove = textureLoad(dataTextureC, clamp(coord + vec2<i32>(jog, -1), vec2<i32>(0), hi), 0).g;
  var water = max(prev.g * 0.94, fromAbove * 0.992);

  // Idea 1 — frame nucleation and a creeping front. Frost forms first on the cold window frame and
  // grows inward from frosted neighbours, faster along the crystal branches, so the front advances
  // as ferns. This is also what makes the file run at all: C starts at zero, so the old
  // `frost < 0.005` early return fired forever and frost never appeared.
  if (frost < 0.005) {
    let edgeDist = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
    let frameSeed = smoothstep(0.03, 0.0, edgeDist + h2(floor(uv * res / 5.0)) * 0.025);
    let frontier = max(max(cN.r, cS.r), max(cE.r, cW.r));
    let grows = h2(vec2<f32>(coord) + fract(t * 7.13) * 91.0) < (0.15 + crystal * 0.7) * (1.0 - clamp(water * 4.0, 0.0, 1.0));
    frost = max(frameSeed * 0.3, select(0.0, frontier * 0.5, frontier > 0.02 && grows));
  }
  if(frost < 0.005) {
    let base = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeTexture, coord, vec4<f32>(base.rgb, base.a * 0.1));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(0.0, water, 0.0, 0.0));
    return;
  }
  // Wet glass holds off the ice: frost thickens more slowly under water.
  frost = clamp(frost + freeze * (1.0 - clamp(water * 3.0, 0.0, 0.9)), 0.0, 1.0);
  let mouse = u.zoom_config.yz;
  let md = distance(uv, mouse);
  let lap = (cN.r + cS.r + cE.r + cW.r) * 0.25 - frost;
  let heat = smoothstep(heatR, heatR * 0.2, md);
  let unmelted = frost;
  frost = frost * (1.0 - heat * 0.9) - lap * heat * 2.0;
  frost = clamp(frost, 0.0, 1.0);
  // Idea 2 (source) — what the warm cursor melts becomes water on the glass.
  water = clamp(water + max(unmelted - frost, 0.0) * 1.6, 0.0, 1.0);
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
  // Idea 2 (display) — a runnel is a thin water lens: it clears the frost it runs through and
  // refracts the view across its width, with a bright meniscus edge.
  let wetEdge = cE.g - cW.g;
  let wetUV = clamp(uv + vec2<f32>(wetEdge * 0.02, -water * 0.004), vec2<f32>(0.0), vec2<f32>(1.0));
  let wetCol = textureSampleLevel(readTexture, u_sampler, wetUV, 0.0).rgb * (1.02 + abs(wetEdge) * 1.5);
  let wet = smoothstep(0.03, 0.25, water);
  col = mix(col, wetCol, wet * 0.85);
  col = aces(col * 1.2);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = mix(luma * 0.15, 0.75 + crystal * 0.25 + caust * 0.35, frost) * (1.0 - wet * 0.35);
  let finalAlpha = mix(alpha * 0.7, min(alpha * 1.15, 1.0), depth);
  textureStore(writeTexture, coord, vec4<f32>(col, finalAlpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, vec4<f32>(frost, water, caust, finalAlpha));
}
