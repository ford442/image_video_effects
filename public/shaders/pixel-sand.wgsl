// ═══════════════════════════════════════════════════════════════════
//  Pixel Sand — Batch 4 Visualist Upgrade
//  Category: simulation
//  Features: upgraded-rgba, mouse-driven, audio-reactive, depth-aware,
//            temporal, aces-tone-map, blackbody-warmth, oklab-mix, ign-dither
//  Complexity: Medium
//  Upgraded: 2026-06-14
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

fn hashf(n: f32) -> f32 { return fract(sin(n * 127.1) * 43758.5453); }
fn hash21(p: vec2<f32>) -> f32 { return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123); }
fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p); let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}
fn curlForce(p: vec2<f32>, t: f32) -> vec2<f32> {
  let eps = 0.05;
  let n1 = valueNoise(p * 3.0 + vec2<f32>(eps, 0.0) + t * 0.1);
  let n2 = valueNoise(p * 3.0 - vec2<f32>(eps, 0.0) + t * 0.1);
  let n3 = valueNoise(p * 3.0 + vec2<f32>(0.0, eps) + t * 0.1);
  let n4 = valueNoise(p * 3.0 - vec2<f32>(0.0, eps) + t * 0.1);
  return vec2<f32>((n3 - n4) / (2.0 * eps), -(n1 - n2) / (2.0 * eps));
}
fn luma(rgb: vec3<f32>) -> f32 { return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722)); }
fn linear_srgb_to_oklab(c: vec3<f32>) -> vec3<f32> {
  let L = 0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b;
  let M = 0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b;
  let S = 0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b;
  let l_ = pow(L, 1.0 / 3.0); let m_ = pow(M, 1.0 / 3.0); let s_ = pow(S, 1.0 / 3.0);
  return vec3<f32>(0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
                   1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
                   0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_);
}
fn oklab_to_linear_srgb(c: vec3<f32>) -> vec3<f32> {
  let l_ = c.x + 0.3963377774 * c.y + 0.2158037573 * c.z;
  let m_ = c.x - 0.1055613458 * c.y - 0.0638541728 * c.z;
  let s_ = c.x - 0.0894841775 * c.y - 1.2914855480 * c.z;
  let l = l_ * l_ * l_; let m = m_ * m_ * m_; let s = s_ * s_ * s_;
  return vec3<f32>(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                  -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                  -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s);
}
fn mixOkLab(a: vec3<f32>, b: vec3<f32>, t: f32) -> vec3<f32> {
  return oklab_to_linear_srgb(mix(linear_srgb_to_oklab(a), linear_srgb_to_oklab(b), t));
}
fn blackbodyRGB(T: f32) -> vec3<f32> {
  let t = clamp(T, 1000.0, 40000.0) / 100.0;
  let r = select(clamp(329.698727446 * pow(t - 60.0, -0.1332047592) / 255.0, 0.0, 1.0), 1.0, t <= 66.0);
  let g = select(clamp(288.1221695283 * pow(t - 60.0, -0.0755148492) / 255.0, 0.0, 1.0),
                 clamp((99.4708025861 * log(t) - 161.1195681661) / 255.0, 0.0, 1.0), t <= 66.0);
  let b = select(select(0.0, clamp((138.5177312231 * log(t - 10.0) - 305.0447927307) / 255.0, 0.0, 1.0), t > 19.0), 1.0, t >= 66.0);
  return vec3<f32>(r, g, b);
}
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn ign(p: vec2<f32>) -> f32 { return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715)))); }
fn readState(cx: i32, cy: i32) -> vec4<f32> {
  let gw = i32(u.config.z); let gh = i32(u.config.w);
  return textureLoad(dataTextureC, vec2<i32>(clamp(cx, 0, gw - 1), clamp(cy, 0, gh - 1)), 0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let res = vec2<f32>(u.config.zw);
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

  let uv01 = vec2<f32>(pixel) / res;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let mDown = u.zoom_config.w > 0.5;
  let p1 = u.zoom_params.x; let p2 = u.zoom_params.y; let p3 = u.zoom_params.z; let p4 = u.zoom_params.w;
  let bass = plasmaBuffer[0].x; let mids = plasmaBuffer[0].y; let treble = plasmaBuffer[0].z;

  let video = textureSampleLevel(readTexture, u_sampler, uv01, 0.0);
  let vidLuma = luma(video.rgb);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv01, 0.0).r;

  var cell = readState(pixel.x, pixel.y);
  let spawnR = hashf(f32(global_id.x) * 73.0 + f32(global_id.y) * 37.0 + 1.0 + time);

  // Warm blackbody spawn under cursor
  let mDist = distance(uv01, mouse);
  let mRad = 0.015 + p3 * 0.06;
  if (mDist < mRad && (mDown || spawnR < 0.2)) {
    let temp = 2800.0 + bass * 3200.0 + spawnR * 600.0;
    cell = vec4<f32>(blackbodyRGB(temp) * (1.0 + bass * 0.5), 1.0);
  }

  // Luma-keyed video-to-sand via OkLab mix
  if (cell.a < 0.5 && vidLuma > 0.5 && spawnR < p2 * 0.3) {
    let hot = blackbodyRGB(3000.0 + treble * 5000.0);
    cell = vec4<f32>(mixOkLab(video.rgb, hot, 0.35) * (1.0 + treble), 1.0);
  }

  // Ripple shockwaves deposit hot grains
  for (var i: i32 = 0; i < 50; i++) {
    let rp = u.ripples[i];
    if (rp.z > 0.0 && time - rp.z > 0.0 && time - rp.z < 0.5 && distance(uv01, rp.xy) < 0.025) {
      let temp = 2500.0 + bass * 2000.0 + mids * 1500.0;
      cell = vec4<f32>(blackbodyRGB(temp), 1.0);
    }
  }

  if (cell.a < 0.5) {
    textureStore(dataTextureB, pixel, vec4<f32>(0.0));
    textureStore(writeTexture, pixel, vec4<f32>(0.0));
    textureStore(writeDepthTexture, pixel, vec4<f32>(0.0));
    return;
  }

  let particleLuma = luma(cell.rgb);
  let heightWeight = 0.5 + particleLuma;
  let grav = mix(0.5, 2.5, p1) * (1.0 + bass * 0.5) * heightWeight;
  var vy = cell.b + grav * (0.04 + p2 * 0.08);
  var vx = cell.g;

  let curl = curlForce(uv01 * 5.0, time) * p3 * 0.5;
  vx += curl.x; vy += curl.y;

  let toM = mouse - uv01;
  if (mDown && length(toM) < 0.25) { vx += toM.x * 0.15; vy += toM.y * 0.15; }
  vx += (spawnR - 0.5) * mids;

  let nx = clamp(pixel.x + i32(round(vx)), 0, i32(res.x) - 1);
  let ny = clamp(pixel.y + i32(round(vy)), 0, i32(res.y) - 1);
  let by = min(pixel.y + 1, i32(res.y) - 1);

  let dest = readState(nx, ny);
  let below = readState(pixel.x, by);
  let bL = readState(pixel.x - 1, by);
  let bR = readState(pixel.x + 1, by);

  let shade = (0.5 + depth * 0.9) * (1.0 + bass * 0.2);
  let bounceDamping = 0.3 + p4 * 0.5;

  var outPos = pixel;
  var moved = false;
  if ((nx != pixel.x || ny != pixel.y) && dest.a < 0.5) {
    cell.g = vx * 0.92; cell.b = vy * 0.88;
    outPos = vec2<i32>(nx, ny); moved = true;
  } else if (below.a < 0.5) {
    cell.g = vx * 0.4; cell.b = 1.0;
    outPos = vec2<i32>(pixel.x, by); moved = true;
  } else if (bL.a < 0.5 && spawnR < 0.5) {
    cell.g = -0.8; cell.b = 0.8;
    outPos = vec2<i32>(max(pixel.x - 1, 0), by); moved = true;
  } else if (bR.a < 0.5) {
    cell.g = 0.8; cell.b = 0.8;
    outPos = vec2<i32>(min(pixel.x + 1, i32(res.x) - 1), by); moved = true;
  } else {
    cell.g = vx * -bounceDamping; cell.b = vy * -bounceDamping;
  }

  // Color: heat-tint via OkLab, ACES, IGN dither
  let speed = sqrt(cell.g * cell.g + cell.b * cell.b);
  let heatTint = blackbodyRGB(2200.0 + particleLuma * 3000.0 + speed * 800.0 + bass * 1200.0);
  var col = mixOkLab(cell.rgb * shade, heatTint, 0.25);
  col = acesToneMap(col * 1.1);
  col += vec3<f32>((ign(vec2<f32>(pixel.xy)) - 0.5) / 255.0);

  let alpha = clamp(luma(col) * 1.4, 0.25, 0.95) * (0.7 + depth * 0.3);
  let a = clamp(alpha, 0.0, 1.0);

  if (moved) { textureStore(dataTextureB, pixel, vec4<f32>(0.0)); }
  textureStore(dataTextureB, outPos, cell);
  textureStore(writeTexture, outPos, vec4<f32>(col * a, a));
  textureStore(writeDepthTexture, outPos, vec4<f32>(depth * a, 0.0, 0.0, 0.0));
}
