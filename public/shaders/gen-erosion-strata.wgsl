// ═══════════════════════════════════════════════════════════════════
//  Erosion Strata
//  Category: generative
//  Features: generative, fbm, voronoi, domain-warping, audio-reactive, mouse-driven
//  Complexity: High
//  Created: 2026-05-31
//  By: Kimi Code CLI
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

fn h12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn n2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(h12(i + vec2<f32>(0.0, 0.0)), h12(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(h12(i + vec2<f32>(0.0, 1.0)), h12(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var x = p;
  for (var i = 0; i < 5; i++) {
    v += a * n2(x);
    x *= 2.0;
    a *= 0.5;
  }
  return v;
}

fn voronoi(p: vec2<f32>, seed: f32) -> vec2<f32> {
  let n = floor(p);
  let f = fract(p);
  var md = 8.0;
  var md2 = 8.0;
  for (var j = -1; j <= 1; j++) {
    for (var i = -1; i <= 1; i++) {
      let g = vec2<f32>(f32(i), f32(j));
      let o = vec2<f32>(h12(n + g + seed), h12(n + g + seed + 7.3));
      let d = dot(g + o - f, g + o - f);
      if (d < md) { md2 = md; md = d; }
      else if (d < md2) { md2 = d; }
    }
  }
  return vec2<f32>(sqrt(md), sqrt(md2));
}

fn aces(c: vec3<f32>) -> vec3<f32> {
  return clamp((c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }
  let uv = vec2<f32>(gid.xy) / res;
  let t = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let erosion = u.zoom_params.x;
  let density = u.zoom_params.y;
  let veins = u.zoom_params.z;
  let water = u.zoom_params.w;
  let warp = vec2<f32>(fbm(uv * 3.0 + t * 0.05 * (1.0 + bass)), fbm(uv * 3.0 + t * 0.05 * (1.0 + bass) + 5.2));
  let wuv = uv + warp * erosion * 0.3;
  let freq = mix(6.0, 24.0, density);
  let lnoise = fbm(wuv * vec2<f32>(freq * 0.5, freq) + vec2<f32>(0.0, t * 0.02 * (1.0 + bass * 0.5)));
  let lh = wuv.y + lnoise * 0.15;
  let li = floor(lh * freq);
  let lf = fract(lh * freq);
  let cnoise = fbm(wuv * vec2<f32>(8.0, 2.0) + vec2<f32>(t * 0.03 * (1.0 + bass), 0.0));
  let cmask = smoothstep(0.35 - erosion * 0.25, 0.65 + erosion * 0.15, cnoise);
  let hard = fbm(vec2<f32>(li * 0.7, 0.0));
  let erAmt = erosion * (1.0 - hard * 0.6) * cmask;
  let exposed = smoothstep(0.0, 0.3 + erAmt * 0.5, lf) * smoothstep(1.0, 0.7 - erAmt * 0.3, lf);
  let edge = min(lf, 1.0 - lf);
  let weather = smoothstep(0.0, 0.15 + erAmt * 0.2, edge);
  let v = voronoi(wuv * vec2<f32>(mix(12.0, 30.0, veins), mix(4.0, 12.0, veins)) + vec2<f32>(li * 3.1, 0.0), li);
  let vein = smoothstep(0.0, 0.08 * (1.0 + treble * 2.0), v.y - v.x) * veins * exposed;
  let era = fract(mids * 0.5 + t * 0.03);
  let sienna = vec3<f32>(0.886, 0.345, 0.133);
  let ochre = vec3<f32>(0.8, 0.467, 0.133);
  let shale = vec3<f32>(0.294, 0.294, 0.294);
  let slate = vec3<f32>(0.439, 0.502, 0.565);
  let sand = vec3<f32>(0.957, 0.643, 0.376);
  let lm = fract(li * 0.17 + h12(vec2<f32>(li, 0.0)));
  var col = select(select(select(select(shale, slate, lm < 0.8), sand, lm < 0.6), ochre, lm < 0.4), sienna, lm < 0.2);
  col = mix(col, select(select(select(select(sienna, ochre, lm < 0.8), sand, lm < 0.6), slate, lm < 0.4), shale, lm < 0.2), era);
  let wet = smoothstep(mix(water, u.zoom_config.z, 0.5), mix(water, u.zoom_config.z, 0.5) - 0.15, uv.y);
  let sss = wet * exposed * (1.0 + bass * 0.8) * 0.4;
  col = col * (0.3 + exposed * 0.7) * weather;
  col = mix(col, vec3<f32>(0.15, 0.12, 0.08), erAmt * 0.5);
  col += vec3<f32>(0.6, 0.55, 0.4) * vein;
  col += vec3<f32>(0.2, 0.35, 0.5) * sss;
  col += vec3<f32>(1.0, 0.95, 0.8) * h12(gid.xy + fract(t * 10.0)) * treble * vein * 3.0;
  col *= mix(1.0, 0.6, wet);
  col += vec3<f32>(0.05, 0.08, 0.12) * wet;
  let striation = sin(lf * freq * 18.84956 + li * 2.0) * 0.5 + 0.5;
  col *= 0.9 + striation * 0.2 * exposed;
  let fossil = smoothstep(0.12, 0.0, length(fract(wuv * 15.0 + li * 4.0) - vec2<f32>(h12(vec2<f32>(li, 3.0)), h12(vec2<f32>(li, 4.0))))) * smoothstep(0.7, 1.0, h12(vec2<f32>(li, 2.0))) * exposed;
  col *= 1.0 - fossil * 0.4;
  col += vec3<f32>(0.08, 0.06, 0.04) * fossil;
  let depth = fbm(uv * 2.0 + vec2<f32>(0.0, 0.5)) * 0.5 + 0.5;
  let haze = 1.0 - exp(-depth * 2.0 * (1.0 + uv.y));
  col = mix(col, vec3<f32>(0.5, 0.55, 0.6), haze * 0.4);
  col = aces(col * 1.2);
  let alpha = exposed * weather * (1.0 - haze * 0.5);
  let a = clamp(alpha, 0.0, 1.0);
  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(col * a, a));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(mix(0.2, 0.9, depth * (1.0 - wet * 0.3)), 0.0, 0.0, 0.0));
}
