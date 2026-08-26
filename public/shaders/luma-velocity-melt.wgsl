// Luma Velocity Melt — exact-load HDR display-history advection.
// A owns untonemapped RGB and semantic alpha; B is intentionally unwritten.
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

fn hash21(p: vec2<f32>) -> f32 { return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123); }
fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p); let f = fract(p); let w = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), w.x), mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), w.x), w.y);
}
fn historyCoord(uv: vec2<f32>, dims: vec2<i32>) -> vec2<i32> { return clamp(vec2<i32>(uv * vec2<f32>(dims)), vec2<i32>(0), dims - vec2<i32>(1)); }
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw; if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }
  let pixel = vec2<i32>(gid.xy); let dims = vec2<i32>(res);
  let uv = (vec2<f32>(gid.xy) + 0.5) / res; let time = u.config.x;
  let aspectVec = vec2<f32>(res.x / max(res.y, 1.0), 1.0);
  let bass = plasmaBuffer[0].x; let mids = plasmaBuffer[0].y; let treble = plasmaBuffer[0].z;
  // These saved controls have non-normalized ranges and are used directly.
  let meltSpeed = max(u.zoom_params.x, 0.0); let heat = max(u.zoom_params.y, 0.0);
  let persistence = clamp(u.zoom_params.z, 0.5, 0.999); let threshold = u.zoom_params.w;
  let source = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let sourceLuma = dot(source.rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  let hot = smoothstep(threshold - 0.12, threshold + 0.12, sourceLuma) * (1.0 + heat * 0.18 + bass * 0.45);
  let nX = noise2(uv * vec2<f32>(8.0, 14.0) + vec2<f32>(time * 0.12, -time * 0.08));
  let nY = noise2(uv.yx * vec2<f32>(11.0, 7.0) + vec2<f32>(4.2, time * 0.1));
  var flow = vec2<f32>((nX - 0.5) * meltSpeed * (1.8 + mids), meltSpeed * hot * (1.0 + (1.0 - depth) * 0.5));

  let mouseDelta = (uv - u.zoom_config.yz) * aspectVec; let mouseDist = length(mouseDelta);
  let mouseMask = exp(-mouseDist * mouseDist * 75.0); let held = select(0.16, 1.0, u.zoom_config.w > 0.5);
  let tangent = select(vec2<f32>(0.0), vec2<f32>(-mouseDelta.y, mouseDelta.x) / mouseDist, mouseDist > 0.001);
  flow += tangent / aspectVec * mouseMask * held * (meltSpeed * 4.0 + 0.004);
  var clickEnergy = 0.0; let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i += 1u) {
    let ripple = u.ripples[i]; let age = time - ripple.z;
    if (age >= 0.0 && age < 2.4) {
      let delta = (uv - ripple.xy) * aspectVec; let dist = length(delta);
      let ring = exp(-pow((dist - age * 0.2) * 42.0, 2.0)) * exp(-age * 1.2);
      let dir = select(vec2<f32>(0.0), delta / dist, dist > 0.001);
      flow += dir / aspectVec * ring * (0.008 + meltSpeed * 2.2); clickEnergy += ring;
    }
  }
  let historyUV = clamp(uv - flow, vec2<f32>(0.001), vec2<f32>(0.999));
  let history = textureLoad(dataTextureC, historyCoord(historyUV, dims), 0);
  let chroma = (0.001 + meltSpeed * 0.7 + treble * 0.002) * normalize(vec2<f32>(flow.x + 0.0001, flow.y + 0.0001));
  let sourceR = textureSampleLevel(readTexture, u_sampler, clamp(uv + chroma, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0);
  let sourceB = textureSampleLevel(readTexture, u_sampler, clamp(uv - chroma, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0);
  let injected = vec4<f32>(sourceR.r, source.g, sourceB.b, max(source.a, max(sourceR.a, sourceB.a)));
  let historyWeight = persistence * history.a * smoothstep(0.001, 0.02, length(flow));
  var hdr = mix(injected.rgb, history.rgb * (0.992 + bass * 0.004), historyWeight);
  hdr += vec3<f32>(1.0, 0.24, 0.04) * hot * heat * 0.045 + vec3<f32>(0.18, 0.4, 1.0) * clickEnergy * mids * 0.08;
  let alpha = clamp(max(injected.a, history.a * persistence) + hot * 0.04 + clickEnergy * 0.05, 0.0, 1.0);
  textureStore(dataTextureA, pixel, vec4<f32>(min(hdr, vec3<f32>(8.0)), alpha));
  textureStore(writeTexture, pixel, vec4<f32>(acesToneMap(hdr), alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(clamp(depth + length(flow) * 0.8 + hot * 0.02, 0.0, 1.0), 0.0, 0.0, 0.0));
}
