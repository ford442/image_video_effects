// ═══════════════════════════════════════════════════════════════════
//  Interactive Origami
//  Category: geometric
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-11
//  Ideas: mountain-valley fold parity; wet-fold shadow along crease tangent
//  A packing: ACES display RGBA
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

fn triWave(x: f32) -> f32 {
  return abs(fract(x * 0.5 + 0.25) * 4.0 - 2.0) - 1.0;
}

fn foldHeight(p: vec2<f32>, mouse2: vec2<f32>, scale: f32, bass: f32) -> f32 {
  let d1 = dot(p - mouse2, normalize(vec2<f32>(0.707, 0.707)));
  let d2 = dot(p - mouse2, normalize(vec2<f32>(-0.707, 0.707)));
  let d3 = dot(p - mouse2, normalize(vec2<f32>(1.0, 0.0)));
  let amp = 1.0 + bass * 0.4;
  return (triWave(d1 * scale) + triWave(d2 * scale * 0.73) + triWave(d3 * scale * 1.27)) * amp / 3.0;
}

fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
  let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  let p = abs(fract(hsv.xxx + k.xyz) * 6.0 - k.www);
  return hsv.z * mix(k.xxx, clamp(p - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), hsv.y);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }
  let pixel = vec2<i32>(gid.xy);
  let uv = vec2<f32>(gid.xy) / max(resolution, vec2<f32>(1.0));
  let time = u.config.x;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let aVec = vec2<f32>(aspect, 1.0);
  let held = f32(u.zoom_config.w > 0.5);

  let foldScale = mix(2.0, 18.0, u.zoom_params.x) * (1.0 + held * 0.28);
  let foldDepth = u.zoom_params.y * 0.06;
  let lightInt = u.zoom_params.z;
  let depthInfl = u.zoom_params.w;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  let depthFactor = mix(1.0, 1.0 + depthInfl, 1.0 - depth);
  let prev = textureLoad(dataTextureC, pixel, 0);

  let mouse = u.zoom_config.yz;
  let mDistVec = (uv - mouse) * aVec;
  let mDist = length(mDistVec);
  let influence = smoothstep(0.85, 0.0, mDist) * mix(1.0, 1.35, held);

  let rippleCount = min(u32(u.config.y), 50u);
  var rippleFold = 0.0;
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i].xy;
    let rAge = time - u.ripples[i].z;
    if (rAge < 0.0 || rAge > 3.5) { continue; }
    let rDist = length((uv - rp) * aVec);
    let rFront = rAge * 0.4;
    rippleFold += exp(-abs(rDist - rFront) * 25.0) * exp(-rAge * 1.2);
  }

  let pUV = uv * aVec;
  let mUV = mouse * aVec;
  let dlt = 0.005;

  // Mountain-valley fold parity: alternate crease sign per grid cell.
  let creaseCell = floor(pUV * foldScale * 0.35);
  let foldParity = select(-1.0, 1.0, (i32(creaseCell.x) + i32(creaseCell.y)) % 2 == 0);

  let h0 = foldHeight(pUV, mUV, foldScale, bass) * foldParity;
  let hDx = foldHeight(pUV + vec2<f32>(dlt, 0.0), mUV, foldScale, bass) * foldParity;
  let hDy = foldHeight(pUV + vec2<f32>(0.0, dlt), mUV, foldScale, bass) * foldParity;
  let grad = vec2<f32>((hDx - h0) / dlt, (hDy - h0) / dlt);
  let creaseDir = select(vec2<f32>(1.0, 0.0), normalize(vec2<f32>(-grad.y, grad.x)), length(grad) > 0.0002);
  let runners = pow(max(0.0, sin(dot(pUV, creaseDir) * 22.0 - time * (6.0 + mids * 4.0))), 11.0) * influence;

  let rippleDisp = rippleFold * 0.015;
  let dispDir = normalize(mDistVec + vec2<f32>(0.0001));
  let disp = (grad * foldDepth + dispDir * rippleDisp) * influence * depthFactor;
  let sampleUV = clamp(uv - disp / aVec, vec2<f32>(0.0), vec2<f32>(1.0));
  var color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;

  let normalXY = normalize(grad + vec2<f32>(0.0001)) * 0.4;
  let normalZ = sqrt(max(0.0, 1.0 - dot(normalXY, normalXY)));
  let normal3 = vec3<f32>(normalXY, normalZ);
  let lightDir = normalize(vec3<f32>(-0.5, -0.5, 1.0));
  let diffuse = max(dot(normal3, lightDir), 0.0);
  let ridgePeak = pow(abs(h0), 3.0) * (1.0 + treble * 0.5);
  let lighting = (diffuse * 0.6 + ridgePeak * 0.4) * lightInt * influence;
  color = clamp(color + lighting, vec3<f32>(0.0), vec3<f32>(1.0));
  let shadow = smoothstep(-0.3, -0.8, h0) * 0.3 * lightInt * influence;
  color *= (1.0 - shadow);

  // Wet-fold shadow: darken valley side along crease tangent.
  let valleyMask = smoothstep(0.08, -0.28, h0);
  let tangentAlign = abs(dot(normalize(grad + vec2<f32>(0.0001)), creaseDir));
  let wetFoldShadow = valleyMask * (0.26 + (1.0 - tangentAlign) * 0.24) * lightInt * influence;
  color *= (1.0 - wetFoldShadow);

  let slick = hsv2rgb(vec3<f32>(fract(0.15 + abs(h0) * 0.35 + mids * 0.18 + time * 0.06), 0.55, 1.0));
  color = mix(color, color * slick * 1.25, (0.16 + treble * 0.14) * clamp(ridgePeak + runners, 0.0, 1.0));
  color += slick * (runners * 0.18 + rippleFold * 0.28);
  color = mix(color, prev.rgb * 0.92, 0.08);
  color = acesToneMap(max(color, vec3<f32>(0.0)));

  let alpha = clamp(dot(color, vec3<f32>(0.33)) * 0.6 + 0.4 + depth * 0.1, 0.0, 1.0);
  let outCol = vec4<f32>(color, alpha);
  textureStore(dataTextureA, pixel, outCol);
  textureStore(writeTexture, pixel, outCol);
  textureStore(writeDepthTexture, pixel, vec4<f32>(clamp(depth + abs(h0) * 0.08 * influence, 0.0, 1.0), 0.0, 0.0, 1.0));
}
