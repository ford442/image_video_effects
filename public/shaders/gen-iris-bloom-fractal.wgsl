// Iris Bloom Fractal — recursive polar petals, aperture, pupil, and veins
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

struct Uniforms { config: vec4<f32>, zoom_config: vec4<f32>, zoom_params: vec4<f32>, ripples: array<vec4<f32>, 50>, };
const TAU: f32 = 6.28318530718;
fn palette(t: f32) -> vec3<f32> { return vec3<f32>(0.5) + vec3<f32>(0.5) * cos(TAU * (vec3<f32>(t) + vec3<f32>(0.02, 0.36, 0.68))); }
fn acesToneMap(x: vec3<f32>) -> vec3<f32> { return clamp((x*(2.51*x+0.03))/(x*(2.43*x+0.59)+0.14), vec3<f32>(0.0), vec3<f32>(1.0)); }

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let res = u.config.zw;
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }
  let uv01 = (vec2<f32>(pixel) + vec2<f32>(0.5)) / res;
  let aspect = res.x / res.y;
  let p = (uv01 - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0);
  let mouse = (u.zoom_config.yz - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0);
  let held = clamp(u.zoom_config.w, 0.0, 1.0);
  let center = mouse * held * 0.42;
  let q = p - center;
  let r = length(q);
  let angle = atan2(q.y, q.x);
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let petalCount = 5.0 + floor(clamp(u.zoom_params.x, 0.0, 1.0) * 15.0 + 0.5);
  let bloomDepth = 1.0 + floor(clamp(u.zoom_params.y, 0.0, 1.0) * 5.0 + 0.5);
  let aperture = mix(0.07, 0.34, clamp(u.zoom_params.z, 0.0, 1.0)) * (1.0 + bass * 0.08);
  let colorCycle = u.zoom_params.w;

  var petals = 0.0;
  var recursive = 0.0;
  for (var i = 0; i < 6; i++) {
    if (f32(i) >= bloomDepth) { break; }
    let fi = f32(i);
    let ringR = aperture + 0.07 + fi * 0.085;
    let lobe = cos(angle * (petalCount + fi * 2.0) + time * (0.08 + fi * 0.025) + mids * 0.18);
    let contour = ringR + lobe * (0.035 + fi * 0.006);
    let layer = exp(-abs(r - contour) * (52.0 - fi * 4.0));
    petals += layer / (1.0 + fi * 0.28);
    recursive += layer * (fi + 1.0) / 6.0;
  }
  let irisMask = (1.0 - smoothstep(0.48, 0.55, r)) * smoothstep(aperture * 0.72, aperture, r);
  let pupil = 1.0 - smoothstep(aperture * 0.82, aperture, r);
  let veinPhase = sin(angle * petalCount * 2.0 + r * (65.0 + treble * 16.0) - time * 0.45);
  let veins = pow(abs(veinPhase), 8.0) * irisMask;
  let limbal = exp(-abs(r - 0.51) * 70.0);

  var clickBloom = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var ri = 0u; ri < rippleCount; ri++) {
    let ripple = u.ripples[ri];
    let age = time - ripple.z;
    if (age > 0.0 && age < 3.2) {
      let clickCenter = (ripple.xy - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0);
      clickBloom += exp(-abs(distance(p, clickCenter) - age * 0.22) * 76.0) * exp(-age * 1.35);
    }
  }
  let hue = angle / TAU + r * 0.8 + colorCycle + time * 0.018 + mids * 0.07;
  var raw = vec3<f32>(0.004, 0.006, 0.012);
  raw += palette(hue) * irisMask * (0.25 + petals * 1.25 + bass * 0.18);
  raw += palette(hue + 0.27) * veins * (0.55 + treble * 0.8);
  raw += vec3<f32>(0.22, 0.58, 1.25) * limbal * (0.6 + mids * 0.3);
  raw += palette(colorCycle + clickBloom * 0.2) * clickBloom * 0.7;
  raw *= 1.0 - pupil * 0.94;
  let prev = textureLoad(dataTextureC, pixel, 0);
  raw = clamp(mix(prev.rgb * 0.94, raw, 0.27 + bloomDepth * 0.012), vec3<f32>(0.0), vec3<f32>(7.0));
  let coverage = clamp(0.025 + irisMask * 0.55 + petals * 0.22 + veins * 0.12 + limbal * 0.12 + clickBloom * 0.12, 0.025, 0.98);
  let depth = clamp(irisMask * 0.28 + recursive * 0.48 + limbal * 0.2, 0.0, 1.0);
  textureStore(dataTextureA, pixel, vec4<f32>(raw, coverage));
  textureStore(writeTexture, pixel, vec4<f32>(acesToneMap(raw * 1.12), coverage));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
