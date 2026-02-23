// ═══════════════════════════════════════════════════════════════
//  Cosmic Web Filament - Generative dark matter web
//  Category: generative
//  Description: Dark matter web with Voronoi filaments, FBM warping, 
//               and mouse gravity wells. Hypnotic cosmic structure.
//  Features: mouse-driven
//  Tags: generative, cosmic, voronoi, filament, organic
//  Author: ford442
// ═══════════════════════════════════════════════════════════════

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

fn hash33(p: vec3<f32>) -> vec3<f32> {
  var p3 = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.xxy + p3.yxx) * p3.zyx);
}

fn voronoi3D(p: vec3<f32>) -> vec2<f32> {
  let i = floor(p);
  let f = fract(p);
  var res = vec2<f32>(8.0, 8.0);
  for (var k: i32 = -1; k <= 1; k++) {
    for (var j: i32 = -1; j <= 1; j++) {
      for (var i_: i32 = -1; i_ <= 1; i_++) {
        let b = vec3<f32>(f32(i_), f32(j), f32(k));
        let r = b - f + hash33(i + b);
        let d = dot(r, r);
        if (d < res.x) {
          res.y = res.x; res.x = d;
        } else if (d < res.y) {
          res.y = d;
        }
      }
    }
  }
  return sqrt(res);
}

fn fbm(p: vec3<f32>) -> f32 {
  var v = 0.0; var a = 0.5;
  for (var i: i32 = 0; i < 5; i++) {
    v += a * voronoi3D(p * (1.0 + f32(i) * 0.5)).x;
    a *= 0.5; 
  }
  return v;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
  let res = u.config.zw;
  if (id.x >= u32(res.x) || id.y >= u32(res.y)) { return; }

  var uv = (vec2<f32>(id.xy) / res - 0.5) * vec2<f32>(res.x / res.y, 1.0) * u.zoom_config.z;

  let mouse = u.zoom_config.yz;
  let warpStrength = u.zoom_params.x * 3.0;
  let density = u.zoom_params.y * 3.5 + 0.5;
  let speed = u.zoom_params.z * 2.0;
  let colorShift = u.zoom_params.w;

  // Mouse gravity well distortion
  let dist = length(uv - mouse);
  let force = smoothstep(0.5, 0.0, dist);
  uv -= normalize(uv - mouse + 0.001) * force * 0.8;

  var p = vec3<f32>(uv * 3.0, u.config.x * speed * 0.3);
  p += fbm(p * 0.4) * warpStrength;

  let v = voronoi3D(p * density);
  let filament = 1.0 / (v.y - v.x + 0.001);

  let filDensity = smoothstep(0.0, 2.0, filament * 0.6);

  var col = vec3<f32>(0.0, 0.02, 0.08);
  
  let hueShift = colorShift * 6.28318;
  let purple = vec3<f32>(0.6, 0.1, 0.8);
  let cyan = vec3<f32>(0.0, 0.9, 1.0);
  
  col = mix(col, purple, smoothstep(0.3, 0.8, filDensity));
  col = mix(col, cyan, smoothstep(0.7, 1.2, filDensity));
  col += pow(filDensity, 3.0) * 0.6;

  textureStore(writeTexture, id.xy, vec4<f32>(col, 1.0));
  textureStore(writeDepthTexture, id.xy, vec4<f32>(filDensity * 0.5, 0.0, 0.0, 0.0));
}
