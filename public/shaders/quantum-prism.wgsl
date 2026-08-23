// ═══════════════════════════════════════════════════════════════════
//  Quantum Prism — Batch 56
//  Hex facet runners, prism caustics, held rotation, click shock fronts
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

const TAU: f32 = 6.28318530718;

fn rotate(v: vec2<f32>, angle: f32) -> vec2<f32> {
  let s = sin(angle);
  let c = cos(angle);
  return vec2<f32>(v.x * c - v.y * s, v.x * s + v.y * c);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

  let uv = vec2<f32>(gid.xy) / dims;
  let aspect = dims.x / dims.y;
  let mouse = u.zoom_config.yz;
  let held = f32(u.zoom_config.w > 0.5);
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let prev = textureLoad(dataTextureC, pixel, 0);

  let intensity = u.zoom_params.x;
  let spinSpeed = mix(0.2, 2.5, u.zoom_params.y) * (1.0 + mids * 0.3);
  let scale = mix(8.0, 22.0, u.zoom_params.z);
  let detail = u.zoom_params.w;

  let uv_aspect = vec2<f32>(uv.x * aspect, uv.y);
  let s = vec2<f32>(1.7320508, 1.0);
  let u_scaled = uv_aspect * scale;
  let ga = (fract(u_scaled / s) - 0.5) * s;
  let ida = floor(u_scaled / s);
  let u_off = u_scaled - s * 0.5;
  let gb = (fract(u_off / s) - 0.5) * s;
  let idb = floor(u_off / s);
  let da = dot(ga, ga);
  let db = dot(gb, gb);

  var localUV = ga;
  var center = (ida + 0.5) * s;
  if (db < da) {
    localUV = gb;
    center = (idb + 0.5) * s + s * 0.5;
  }

  let centerUV = vec2<f32>(center.x / scale / aspect, center.y / scale);
  let mouseVec = (mouse - centerUV) * vec2<f32>(aspect, 1.0);
  let dist = length(mouseVec);
  let influence = smoothstep(0.4, 0.0, dist) * intensity;

  let rotAngle = influence * 3.14159 + time * spinSpeed * 0.15 + held * 0.4;
  let rotatedLocal = rotate(localUV, rotAngle);
  let zoom = 1.0 - influence * 0.5;
  let finalUV_scaled = center + rotatedLocal * zoom;
  let finalUV = vec2<f32>(finalUV_scaled.x / scale / aspect, finalUV_scaled.y / scale);

  let ca = influence * mix(0.01, 0.04, detail);
  let rOffset = rotate(vec2<f32>(ca, 0.0), rotAngle);
  let bOffset = rotate(vec2<f32>(ca, 0.0), rotAngle + 2.094);
  let gOffset = rotate(vec2<f32>(ca, 0.0), rotAngle + 4.188);

  let r = textureSampleLevel(readTexture, u_sampler, finalUV + rOffset, 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, finalUV + gOffset, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, finalUV + bOffset, 0.0).b;
  var color = vec3<f32>(r, g, b);

  let edge = smoothstep(0.45, 0.5, length(localUV));
  let facetRunner = smoothstep(0.06, 0.0, abs(fract(length(localUV) * 4.0 - time * (2.0 + bass)) - 0.5));
  let oilSlick = 0.5 + 0.5 * cos(TAU * (vec3<f32>(rotAngle * 0.3 + time * 0.2) + vec3<f32>(0.0, 0.33, 0.67)));
  color = mix(color, vec3<f32>(0.0), edge * influence);
  color += oilSlick * facetRunner * influence * 0.25;
  color += vec3<f32>(0.2, 0.5, 1.0) * influence * 0.2;

  var clickRing = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (rp.z > 0.0 && age >= 0.0 && age < 1.5) {
      let d = length(uv - rp.xy);
      clickRing = max(clickRing, exp(-abs(d - age * 0.3) * 55.0) * (1.0 - age / 1.5));
    }
  }
  color += oilSlick * clickRing * 0.35;

  color = mix(color, prev.rgb * 0.92, 0.1 * influence);
  let centerSample = textureSampleLevel(readTexture, u_sampler, clamp(finalUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let alpha = centerSample.a;
  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  let finalPixel = vec4<f32>(color, alpha);

  textureStore(writeTexture, pixel, finalPixel);
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, pixel, finalPixel);
}
