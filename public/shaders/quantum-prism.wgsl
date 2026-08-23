// ═══════════════════════════════════════════════════════════════════
//  Quantum Prism — Batch 56 merge
//  Honeycomb bevels, spectral bands, oil-slick facet runners, held
//  deformation, click fronts, facet depth, light display history in A
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
  let time = u.config.x;
  let intensity = u.zoom_params.x;
  let motionSpeed = mix(0.15, 3.5, u.zoom_params.y);
  let gridScale = mix(5.0, 32.0, u.zoom_params.z);
  let facetDetail = mix(1.0, 9.0, u.zoom_params.w);
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
  let prev = textureLoad(dataTextureC, pixel, 0);

  let scale = gridScale;
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
  var cellID = ida;
  var center = (ida + 0.5) * s;
  if (db < da) {
    localUV = gb;
    cellID = idb + 0.5;
    center = (idb + 0.5) * s + s * 0.5;
  }

  let centerUV = vec2<f32>(center.x / scale / aspect, center.y / scale);
  let mouseVec = (mouse - centerUV) * vec2<f32>(aspect, 1.0);
  let dist = length(mouseVec);

  let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
  var clickFront = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let event = u.ripples[i];
    let age = max(time - event.z, 0.0);
    clickFront += exp(-age * 1.8) * exp(-abs(length((uv - event.xy) * vec2<f32>(aspect, 1.0)) - age * 0.4) * 60.0);
  }
  let influence = smoothstep(0.4, 0.0, dist) * (0.35 + intensity * 0.65)
    + held * smoothstep(0.32, 0.0, dist)
    + clickFront * 0.35;

  let rotAngle = influence * 3.14159
    + time * motionSpeed * 0.18
    + sin(dot(cellID, vec2<f32>(1.7, 2.3)) + time * motionSpeed) * 0.12
    + held * 0.25;
  let rotatedLocal = rotate(localUV, rotAngle);
  let zoom = 1.0 - influence * 0.5;
  let finalUV_scaled = center + rotatedLocal * zoom;
  let finalUV = vec2<f32>(finalUV_scaled.x / scale / aspect, finalUV_scaled.y / scale);

  let ca = (0.002 + intensity * 0.025) * (influence + audio.z * 0.25);
  let rOffset = rotate(vec2<f32>(ca, 0.0), rotAngle);
  let bOffset = rotate(vec2<f32>(ca, 0.0), rotAngle + 2.094);
  let gOffset = rotate(vec2<f32>(ca, 0.0), rotAngle + 4.188);

  let r = textureSampleLevel(readTexture, u_sampler, finalUV + rOffset, 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, finalUV + gOffset, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, finalUV + bOffset, 0.0).b;
  var color = vec3<f32>(r, g, b);

  let hexDistance = max(abs(localUV.x) * 0.866025 + abs(localUV.y) * 0.5, abs(localUV.y));
  let edge = smoothstep(0.42, 0.50, hexDistance);
  let bevel = pow(clamp(1.0 - hexDistance * 2.0, 0.0, 1.0), facetDetail * 0.35);
  let spectralBand = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.094, 4.188) + hexDistance * facetDetail * 8.0 - time * motionSpeed * 2.0);
  let facetRunner = smoothstep(0.06, 0.0, abs(fract(length(localUV) * 4.0 - time * (2.0 + audio.x)) - 0.5));
  let oilSlick = 0.5 + 0.5 * cos(TAU * (vec3<f32>(rotAngle * 0.3 + time * 0.2) + vec3<f32>(0.0, 0.33, 0.67)));

  color = mix(color, vec3<f32>(0.0), edge * influence);
  color += spectralBand * (bevel * 0.18 + clickFront * 0.25 + audio * 0.12) * intensity;
  color += oilSlick * facetRunner * influence * 0.20;
  color = mix(color, prev.rgb * 0.92, 0.1 * influence);

  let centerSample = textureSampleLevel(readTexture, u_sampler, clamp(finalUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  let depthOut = clamp(mix(depth, 0.18 + bevel * 0.72, 0.3 * intensity), 0.0, 1.0);
  let finalPixel = vec4<f32>(color, centerSample.a);

  textureStore(writeTexture, pixel, finalPixel);
  textureStore(writeDepthTexture, pixel, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, pixel, finalPixel);
}
