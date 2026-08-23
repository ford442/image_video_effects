// Rainy Window — persistent wetness/rivulet field with a sprung hand wiper.
// Raw A ownership: R=wetness, G=downward flow, B=thickness, A=coverage.

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

fn clampPixel(p: vec2<i32>, dims: vec2<i32>) -> vec2<i32> { return clamp(p, vec2<i32>(0), dims - vec2<i32>(1)); }
fn hash21(p: vec2<f32>) -> f32 { return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123); }
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }
  let pixel = vec2<i32>(gid.xy); let dims = vec2<i32>(resolution);
  let uv = (vec2<f32>(gid.xy) + 0.5) / resolution; let time = u.config.x;
  let aspectVec = vec2<f32>(resolution.x / max(resolution.y, 1.0), 1.0);
  let bass = plasmaBuffer[0].x; let mids = plasmaBuffer[0].y; let treble = plasmaBuffer[0].z;
  let rainIntensity = u.zoom_params.x; let wiperRadius = mix(0.035, 0.24, u.zoom_params.y);
  let distortion = u.zoom_params.z; let drySpeed = u.zoom_params.w;

  let c = textureLoad(dataTextureC, pixel, 0);
  let l = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(-1, 0), dims), 0);
  let r = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(1, 0), dims), 0);
  let d = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(0, -1), dims), 0);
  let t = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(0, 1), dims), 0);
  var wetness = clamp(c.r, 0.0, 1.0); var flow = clamp(c.g, 0.0, 1.0); var thickness = clamp(c.b, 0.0, 1.0);

  let hasSpring = arrayLength(&extraBuffer) >= 139u;
  var wiper = u.zoom_config.yz; var wiperVelocity = vec2<f32>(0.0);
  if (hasSpring && extraBuffer[138] > 0.5) {
    wiper = vec2<f32>(extraBuffer[133], extraBuffer[134]); wiperVelocity = vec2<f32>(extraBuffer[135], extraBuffer[136]);
  }
  if (hasSpring && gid.x == 0u && gid.y == 0u) {
    var p = wiper; var v = wiperVelocity; let seeded = extraBuffer[138] > 0.5;
    if (!seeded) { p = u.zoom_config.yz; v = vec2<f32>(0.0); }
    let dt = select(0.0, clamp(time - extraBuffer[137], 0.0, 0.05), seeded);
    v += ((u.zoom_config.yz - p) * 210.0 - v * 27.0) * dt; p += v * dt;
    extraBuffer[133] = p.x; extraBuffer[134] = p.y; extraBuffer[135] = v.x; extraBuffer[136] = v.y;
    extraBuffer[137] = time; extraBuffer[138] = 1.0;
  }

  // Stable rain cells fall at deterministic phases instead of frame-hash noise.
  let rainScale = mix(18.0, 42.0, rainIntensity);
  let cell = floor(vec2<f32>(uv.x * rainScale, uv.y * rainScale * 0.62));
  let seed = hash21(cell); let fall = fract(seed + time * (0.08 + rainIntensity * 0.18 + bass * 0.08));
  let local = fract(vec2<f32>(uv.x * rainScale, uv.y * rainScale * 0.62));
  let dropDelta = vec2<f32>(local.x - (0.18 + seed * 0.64), local.y - fall);
  let drop = exp(-dot(dropDelta * vec2<f32>(6.5, 13.0), dropDelta * vec2<f32>(6.5, 13.0)))
    * step(0.72 - rainIntensity * 0.45 - bass * 0.08, seed);
  let tail = exp(-abs(dropDelta.x) * 18.0) * smoothstep(0.0, 0.65, dropDelta.y) * exp(-dropDelta.y * 5.0) * drop;
  let neighborAverage = (l.r + r.r + d.r + t.r) * 0.25;
  wetness = mix(wetness, neighborAverage, 0.015 + mids * 0.005);
  wetness = clamp(wetness + drop * (0.11 + rainIntensity * 0.12) + tail * 0.05 - (0.0008 + drySpeed * 0.008), 0.0, 1.0);
  flow = clamp(flow * 0.965 + max(t.r - c.r, 0.0) * 0.16 + tail * 0.08, 0.0, 1.0);

  var splash = 0.0; let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i += 1u) {
    let ripple = u.ripples[i]; let age = time - ripple.z;
    if (age >= 0.0 && age < 1.6) {
      let dist = length((uv - ripple.xy) * aspectVec);
      let core = exp(-dist * dist * 120.0) * exp(-age * 2.2);
      let ring = exp(-pow((dist - age * 0.2) * 45.0, 2.0)) * exp(-age * 1.7);
      splash += core + ring * 0.55;
    }
  }
  wetness = clamp(wetness + splash * (0.24 + rainIntensity * 0.26), 0.0, 1.0);

  let wipeDelta = (uv - wiper) * aspectVec; let wipeDist = length(wipeDelta);
  let blade = smoothstep(wiperRadius, wiperRadius * 0.35, wipeDist);
  let wipeStrength = blade * select(0.12, 0.96, u.zoom_config.w > 0.5);
  wetness *= 1.0 - wipeStrength; flow *= 1.0 - wipeStrength;
  thickness = clamp(mix(thickness, wetness + flow * 0.22, 0.12) + splash * 0.04, 0.0, 1.0);
  let coverage = clamp(max(c.a * (0.988 - drySpeed * 0.006), wetness), 0.0, 1.0);
  textureStore(dataTextureA, pixel, vec4<f32>(wetness, flow, thickness, coverage));

  let gradient = vec2<f32>(l.r - r.r, d.r - t.r) * (4.0 + distortion * 16.0);
  let normal = normalize(vec3<f32>(gradient + vec2<f32>(0.0, flow * 0.18), 0.3));
  let sourceUV = clamp(uv + normal.xy * (0.006 + distortion * 0.045) * thickness / aspectVec, vec2<f32>(0.001), vec2<f32>(0.999));
  let source = textureSampleLevel(readTexture, u_sampler, sourceUV, 0.0);
  let fresnel = 0.02 + 0.98 * pow(clamp(1.0 - normal.z, 0.0, 1.0), 5.0);
  let light = normalize(vec3<f32>(-0.45, 0.55, 0.75));
  let specular = pow(max(dot(normal, light), 0.0), 44.0) * thickness;
  let absorption = exp(-thickness * vec3<f32>(0.17, 0.07, 0.025));
  let color = source.rgb * absorption + vec3<f32>(0.56, 0.78, 1.05) * fresnel * (0.15 + mids * 0.12)
    + vec3<f32>(1.1, 1.02, 0.9) * specular * (0.55 + treble * 0.5) + vec3<f32>(0.2, 0.48, 0.9) * splash * bass * 0.12;
  let alpha = clamp(source.a + (1.0 - source.a) * coverage * (0.18 + thickness * 0.58) + fresnel * 0.06, 0.0, 1.0);
  textureStore(writeTexture, pixel, vec4<f32>(acesToneMap(color), alpha));
  let sourceDepth = textureLoad(readDepthTexture, pixel, 0).r;
  textureStore(writeDepthTexture, pixel, vec4<f32>(max(sourceDepth * 0.94, thickness * 0.12), 0.0, 0.0, 0.0));
}
