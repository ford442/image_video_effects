// Liquid Smear Structure — Codex (e) structure-tensor paint transport.
// A/C packing: display RGBA history. B and extraBuffer are intentionally unused.
// History is read only through bounded, exact textureLoad operations.

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

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) /
    max(x * (2.43 * x + 0.59) + 0.14, vec3<f32>(0.001)),
    vec3<f32>(0.0), vec3<f32>(1.0));
}

fn sourceAt(uv: vec2<f32>) -> vec4<f32> {
  return textureSampleLevel(readTexture, u_sampler,
    clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
}

fn lumaAt(uv: vec2<f32>) -> f32 {
  return dot(sourceAt(uv).rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn historyAt(uv: vec2<f32>, dims: vec2<i32>) -> vec4<f32> {
  let p = clamp(vec2<i32>(floor(uv * vec2<f32>(dims))),
    vec2<i32>(0), dims - vec2<i32>(1));
  return textureLoad(dataTextureC, p, 0);
}

fn palette(t: f32) -> vec3<f32> {
  return 0.55 + 0.45 * cos(6.283185 *
    (vec3<f32>(t) + vec3<f32>(0.00, 0.31, 0.67)));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let dims = vec2<i32>(res);
  let uv = (vec2<f32>(gid.xy) + 0.5) / res;
  let texel = 1.0 / res;
  let aspect = res.x / max(res.y, 1.0);
  let time = u.config.x;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));

  let memory = mix(0.76, 0.975, u.zoom_params.x);
  let streamline = mix(1.0, 7.0, u.zoom_params.y);
  let tensorGain = mix(0.45, 4.2, u.zoom_params.z);
  let brushForce = mix(0.15, 1.5, u.zoom_params.w);

  let gx = lumaAt(uv + vec2<f32>(texel.x, 0.0)) -
    lumaAt(uv - vec2<f32>(texel.x, 0.0));
  let gy = lumaAt(uv + vec2<f32>(0.0, texel.y)) -
    lumaAt(uv - vec2<f32>(0.0, texel.y));
  let gradient = vec2<f32>(gx, gy);
  let energy = dot(gradient, gradient);
  let tangent = vec2<f32>(-gradient.y, gradient.x) / max(sqrt(energy), 0.0001);
  let coherence = 1.0 - exp(-energy * 32.0 * tensorGain);

  let p = (uv - 0.5) * vec2<f32>(aspect, 1.0);
  let conveyor = sin(dot(p, tangent * vec2<f32>(1.0 / aspect, 1.0)) * 42.0 -
    time * (2.4 + audio.y * 4.0));
  var flow = tangent * texel * streamline *
    (0.45 + coherence * 1.6 + conveyor * 0.22);
  flow += vec2<f32>(-tangent.y, tangent.x) * texel *
    sin(time * 1.7 + energy * 70.0) * audio.z * 1.8;

  let mouseP = (u.zoom_config.yz - 0.5) * vec2<f32>(aspect, 1.0);
  let mouseDelta = p - mouseP;
  let mouseDist = max(length(mouseDelta), 0.0001);
  let held = clamp(u.zoom_config.w, 0.0, 1.0);
  let brush = exp(-mouseDist * mouseDist * 46.0) * held;
  flow += vec2<f32>(-mouseDelta.y / aspect, mouseDelta.x) / mouseDist *
    brush * 0.018 * brushForce;
  flow -= vec2<f32>(mouseDelta.x / aspect, mouseDelta.y) / mouseDist *
    brush * 0.006 * brushForce;

  var clickLight = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let event = u.ripples[i];
    let age = time - event.z;
    if (age >= 0.0 && age < 3.0) {
      let q = (uv - event.xy) * vec2<f32>(aspect, 1.0);
      let d = max(length(q), 0.0001);
      let front = sin((d - age * 0.34) * 64.0) *
        exp(-abs(d - age * 0.34) * 22.0 - age * 0.8);
      flow += vec2<f32>(q.x / aspect, q.y) / d * front * 0.012 * brushForce;
      clickLight += abs(front);
    }
  }

  flow = clamp(flow, vec2<f32>(-0.065), vec2<f32>(0.065));
  let advectedUV = clamp(uv - flow, vec2<f32>(0.0), vec2<f32>(1.0));
  let history = historyAt(advectedUV, dims);

  var lic = vec3<f32>(0.0);
  var weight = 0.0;
  for (var j = -3; j <= 3; j = j + 1) {
    let fj = f32(j);
    let w = 1.0 - abs(fj) * 0.18;
    lic += sourceAt(uv + tangent * texel * fj * streamline).rgb * w;
    weight += w;
  }
  lic /= max(weight, 0.001);

  let angle = atan2(tangent.y, tangent.x) * 0.15915494 + 0.5;
  let spectral = palette(angle + time * 0.025 + audio.y * 0.1);
  var fresh = mix(lic, spectral * (0.35 + lumaAt(uv)),
    clamp(coherence * 0.62 + audio.x * 0.12, 0.0, 0.82));
  fresh += spectral * (clickLight * 0.12 + brush * 0.18 + audio.z * 0.05);
  let historyMix = memory * (1.0 - clickLight * 0.12);
  let rgbLinear = mix(fresh, clamp(history.rgb, vec3<f32>(0.0), vec3<f32>(3.0)), historyMix);
  let sourceAlpha = sourceAt(advectedUV).a;
  let alpha = clamp(mix(sourceAlpha, history.a, memory * 0.72) +
    coherence * 0.08 + brush * 0.12, 0.0, 1.0);
  let packed = vec4<f32>(rgbLinear, alpha);

  textureStore(dataTextureA, coord, packed);
  textureStore(writeTexture, coord, vec4<f32>(aces(rgbLinear), alpha));
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler,
    advectedUV, 0.0).r;
  textureStore(writeDepthTexture, coord,
    vec4<f32>(clamp(depth - coherence * 0.012 - brush * 0.018, 0.0, 1.0), 0.0, 0.0, 0.0));
}
