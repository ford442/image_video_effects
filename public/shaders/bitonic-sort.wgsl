// ═══════════════════════════════════════════════════════════════════
//  Bitonic Pixel Sort — Algorithmist Upgrade
//  Category: simulation
//  Features: mouse-driven, temporal
//  Complexity: High
//  Chunks: FBM curl noise, SDF smooth union, true bitonic sort
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
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=unused, y=MouseX, z=MouseY, w=unused
  zoom_params: vec4<f32>,  // x=Intensity, y=Speed, z=Scale, w=Detail
  ripples: array<vec4<f32>, 50>,
};

var<workgroup> sKey: array<f32, 256>;
var<workgroup> sCol: array<vec4<f32>, 256>;

fn hash22(p: vec2<f32>) -> vec2<f32> {
  let n = sin(dot(p, vec2<f32>(127.1, 311.7)));
  return fract(vec2<f32>(n, n * 43758.5453));
}

fn vnoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash22(i).x, hash22(i + vec2<f32>(1.0, 0.0)).x, u.x),
             mix(hash22(i + vec2<f32>(0.0, 1.0)).x, hash22(i + vec2<f32>(1.0, 1.0)).x, u.x), u.y);
}

fn curl2D(p: vec2<f32>) -> vec2<f32> {
  let e = 0.01;
  let n = vnoise(p);
  let dx = vnoise(p + vec2<f32>(e, 0.0)) - n;
  let dy = vnoise(p + vec2<f32>(0.0, e)) - n;
  return vec2<f32>(-dy, dx) / e;
}

fn fbmCurl(p: vec2<f32>, octaves: i32) -> vec2<f32> {
  var v = vec2<f32>(0.0);
  var a = 0.5;
  var pp = p;
  for (var i: i32 = 0; i < octaves; i = i + 1) {
    v = v + a * curl2D(pp);
    pp = pp * 2.0 + vec2<f32>(3.1, 1.7);
    a = a * 0.5;
  }
  return v;
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
  let h = max(k - abs(a - b), 0.0) / k;
  return min(a, b) - h * h * k * 0.25;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>,
        @builtin(local_invocation_id) lid: vec3<u32>,
        @builtin(workgroup_id) wgid: vec3<u32>) {
  let li = lid.y * 16u + lid.x;
  let gx = wgid.x * 16u + lid.x;
  let gy = wgid.y * 16u + lid.y;
  let x = i32(gx);
  let y = i32(gy);
  let uv = vec2<f32>(f32(gx), f32(gy)) / u.config.zw;
  let time = u.config.x;

  let scale = 2.0 + u.zoom_params.z * 10.0;
  let speed = u.zoom_params.y * 0.5;
  let warp = fbmCurl(uv * scale + time * speed, i32(2.0 + u.zoom_params.w * 5.0)) * (0.02 + u.zoom_params.z * 0.03);
  let warpedUV = uv + warp;

  var p = textureSampleLevel(readTexture, u_sampler, warpedUV, 0.0);

  let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
  var d = distance(uv, mouse) - (0.1 + u.zoom_params.z * 0.2);
  for (var i: i32 = 0; i < 50; i = i + 1) {
    let rp = u.ripples[i];
    if (rp.z > 0.0) {
      let age = time - rp.z;
      if (age > 0.0 && age < 4.0) {
        let rd = distance(uv, rp.xy) - (0.15 * (1.0 - age / 4.0));
        d = smin(d, rd, 0.15);
      }
    }
  }
  let mask = 1.0 - smoothstep(-0.05, 0.05, d);

  let n = vnoise(uv * scale * 2.0 + time * speed);
  let lum = dot(p.rgb, vec3<f32>(0.299, 0.587, 0.114));
  let key = lum + n * 0.2 * mask + f32(li) * 0.00001;

  sKey[li] = key;
  sCol[li] = p;

  for (var k: u32 = 2u; k <= 256u; k = k << 1u) {
    for (var j: u32 = k >> 1u; j > 0u; j = j >> 1u) {
      workgroupBarrier();
      let partner = li ^ j;
      let bit = li & k;
      let a = sKey[li];
      let b = sKey[partner];
      let asc = bit == 0u;
      let swap = select(a > b, a < b, asc);
      if (swap && partner > li) {
        sKey[li] = b;
        sKey[partner] = a;
        let ca = sCol[li];
        sCol[li] = sCol[partner];
        sCol[partner] = ca;
      }
      workgroupBarrier();
    }
  }

  let sorted = sCol[li];
  let finalCol = mix(p, sorted, u.zoom_params.x * mask);
  textureStore(writeTexture, vec2<i32>(x, y), finalCol);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, vec2<i32>(x, y), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
