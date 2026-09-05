// ═══════════════════════════════════════════════════════════════════
//  Interactive Emboss — Batch 58E
//  Mouse-aimed relief with sprung light, bevel ridges, traveling
//  highlight packets, oil-slick phosphor on crests, held-drag punch,
//  bounded click dents. Display RGBA in A. extraBuffer[133..137] is
//  the existing critically-damped light spring (0,0 writer only).
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

fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
  let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  let p = abs(fract(hsv.xxx + k.xyz) * 6.0 - k.www);
  return hsv.z * mix(k.xxx, clamp(p - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), hsv.y);
}

fn luma(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let pixel = vec2<i32>(global_id.xy);
  var uv = vec2<f32>(global_id.xy) / max(resolution, vec2<f32>(1.0));
  let texel = 1.0 / max(resolution, vec2<f32>(1.0));
  let aspect = resolution.x / max(resolution.y, 1.0);
  let time = u.config.x;
  let held = f32(u.zoom_config.w > 0.5);
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let prev = textureLoad(dataTextureC, pixel, 0);
  let depth = textureLoad(readDepthTexture, pixel, 0).r;

  var mouse = u.zoom_config.yz;
  let hasState = arrayLength(&extraBuffer) > 137u;
  if (global_id.x == 0u && global_id.y == 0u && hasState) {
    let prevTime = extraBuffer[137];
    let dt = clamp(time - prevTime, 0.001, 0.05);
    var sPos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    var sVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (prevTime <= 0.0) {
      sPos = mouse;
      sVel = vec2<f32>(0.0, 0.0);
    }
    let omega = mix(8.0, 14.0, held);
    let accel = (mouse - sPos) * (omega * omega) - sVel * (2.0 * omega);
    sVel = sVel + accel * dt;
    sPos = sPos + sVel * dt;
    extraBuffer[133] = sPos.x;
    extraBuffer[134] = sPos.y;
    extraBuffer[135] = sVel.x;
    extraBuffer[136] = sVel.y;
    extraBuffer[137] = time;
  }
  if (hasState) {
    mouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  }

  let light_vec = (mouse - uv) * vec2<f32>(aspect, 1.0);
  var light_dir = vec2<f32>(0.0, 0.0);
  if (length(light_vec) > 0.001) {
    light_dir = normalize(light_vec);
  }

  let strength = u.zoom_params.x * 5.0 * (1.0 + bass * 0.5) * (1.0 + held * 0.35);
  let mix_amt = u.zoom_params.y;
  let color_mode = u.zoom_params.z;
  var reliefContrast = (0.5 + u.zoom_params.w * 1.5) * mix(0.7, 1.3, depth);

  let l = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-texel.x, 0.0), 0.0).rgb;
  let r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(texel.x, 0.0), 0.0).rgb;
  let t = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -texel.y), 0.0).rgb;
  let b = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, texel.y), 0.0).rgb;
  let grad = vec2<f32>(luma(l) - luma(r), luma(t) - luma(b));
  let n2 = normalize(vec3<f32>(-grad.x * 8.0, -grad.y * 8.0, 1.0));
  let bevel = pow(max(1.0 - abs(dot(n2.xy, light_dir)), 0.0), 6.0);

  var diff = dot(grad, light_dir) * strength * reliefContrast * (1.0 + mids * 0.3);
  let ridgeDir = select(vec2<f32>(1.0, 0.0), normalize(vec2<f32>(-grad.y, grad.x)), length(grad) > 0.0002);
  let packets = pow(max(0.0, sin(dot(uv * vec2<f32>(aspect, 1.0), ridgeDir) * 38.0 - time * (7.0 + treble * 6.0))), 10.0);
  diff = diff + packets * 0.12 * strength * (0.35 + held);

  var stamp = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age < 0.0 || age > 1.2) { continue; }
    let fade = 1.0 - age / 1.2;
    let rpDist = distance(uv, rp.xy);
    let core = exp(-rpDist * rpDist * 240.0) * max(1.0 - age * 4.0, 0.0);
    let ring = exp(-pow((rpDist - age * 0.5) * 28.0, 2.0));
    stamp = stamp + (core * 1.2 + ring * 0.5) * fade * fade;
  }
  diff = diff + stamp * (0.3 + 0.1 * strength) * reliefContrast;

  let c = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let gray_emboss = vec3<f32>(0.5 + diff);
  let color_emboss = c + vec3<f32>(diff);
  let result_emboss = mix(gray_emboss, color_emboss, step(0.5, color_mode));
  let peak = max(result_emboss.r, max(result_emboss.g, result_emboss.b));
  let emboss_final = clamp(result_emboss / (1.0 + max(peak - 1.0, 0.0)), vec3<f32>(0.0), vec3<f32>(1.0));
  var final_color = mix(emboss_final, c, 1.0 - mix_amt);

  let slick = hsv2rgb(vec3<f32>(fract(0.08 + abs(diff) * 2.4 + mids * 0.2 + time * 0.12), 0.72, 1.0));
  final_color = mix(final_color, final_color * slick * 1.2, (0.14 + treble * 0.18) * clamp(abs(diff) * 3.0 + bevel, 0.0, 1.0));
  final_color += slick * (packets * 0.16 + stamp * 0.28 + bevel * 0.12);
  final_color = mix(final_color, prev.rgb * 0.9, 0.16);

  let alpha = clamp(abs(diff) * 2.0 + mix_amt * 0.3 + treble * 0.2 + 0.15, 0.0, 1.0);
  let outCol = vec4<f32>(final_color, mix(alpha, prev.a * 0.9, 0.16));
  textureStore(writeTexture, pixel, outCol);
  textureStore(dataTextureA, pixel, outCol);
  textureStore(writeDepthTexture, pixel, vec4<f32>(clamp(depth + abs(diff) * 0.08 + stamp * 0.05, 0.0, 1.0), 0.0, 0.0, 0.0));
}
