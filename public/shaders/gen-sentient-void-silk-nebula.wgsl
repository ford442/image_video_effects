// ----------------------------------------------------------------
// Sentient Void-Silk Nebula
// Category: generative
// ----------------------------------------------------------------
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
  config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // .x = Flow Speed, .y = Thread Density, .z = Vortex Strength, .w = Iridescence Shift
  ripples: array<vec4<f32>, 50>,
};

// --- Constants & Utilities ---
const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn palette(t: f32) -> vec3<f32> {
    return 0.5 + 0.5 * cos(TAU * (t + vec3<f32>(0.0, 0.33, 0.67)));
}

// 3D Curl Noise implementation
fn mod289(x: vec4<f32>) -> vec4<f32> {
  return x - floor(x * (1.0 / 289.0)) * 289.0;
}
fn permute(x: vec4<f32>) -> vec4<f32> {
  return mod289(((x*34.0)+1.0)*x);
}
fn taylorInvSqrt(r: vec4<f32>) -> vec4<f32> {
  return 1.79284291400159 - 0.85373472095314 * r;
}

fn snoise(v: vec3<f32>) -> f32 {
  let C = vec2<f32>(1.0/6.0, 1.0/3.0);
  let D = vec4<f32>(0.0, 0.5, 1.0, 2.0);

  var i  = floor(v + dot(v, C.yyy));
  let x0 = v - i + dot(i, C.xxx);

  let g = step(x0.yzx, x0.xyz);
  let l = 1.0 - g;
  let i1 = min(g.xyz, l.zxy);
  let i2 = max(g.xyz, l.zxy);

  let x1 = x0 - i1 + C.xxx;
  let x2 = x0 - i2 + C.yyy;
  let x3 = x0 - D.yyy;

  let i_mod = mod289(vec4<f32>(i.x, i.y, i.z, 0.0));
  let p = permute(permute(permute(
             vec4<f32>(i_mod.z) + vec4<f32>(0.0, i1.z, i2.z, 1.0) )
           + vec4<f32>(i_mod.y) + vec4<f32>(0.0, i1.y, i2.y, 1.0) )
           + vec4<f32>(i_mod.x) + vec4<f32>(0.0, i1.x, i2.x, 1.0) );

  let n_ = 0.142857142857;
  let ns = n_ * D.wyz - D.xzx;

  let j = p - 49.0 * floor(p * ns.z * ns.z);

  let x_ = floor(j * ns.z);
  let y_ = floor(j - 7.0 * x_);

  let x = x_ *ns.x + ns.yyyy;
  let y = y_ *ns.x + ns.yyyy;
  let h = 1.0 - abs(x) - abs(y);

  let b0 = vec4<f32>(x.xy, y.xy);
  let b1 = vec4<f32>(x.zw, y.zw);

  let s0 = floor(b0)*2.0 + 1.0;
  let s1 = floor(b1)*2.0 + 1.0;
  let sh = -step(h, vec4<f32>(0.0));

  let a0 = vec4<f32>(b0.x, b0.z, b0.y, b0.w) + vec4<f32>(s0.x, s0.z, s0.y, s0.w) * vec4<f32>(sh.x, sh.x, sh.y, sh.y);
  let a1 = vec4<f32>(b1.x, b1.z, b1.y, b1.w) + vec4<f32>(s1.x, s1.z, s1.y, s1.w) * vec4<f32>(sh.z, sh.z, sh.w, sh.w);

  var p0 = vec3<f32>(a0.xy, h.x);
  var p1 = vec3<f32>(a0.zw, h.y);
  var p2 = vec3<f32>(a1.xy, h.z);
  var p3 = vec3<f32>(a1.zw, h.w);

  let norm = taylorInvSqrt(vec4<f32>(dot(p0,p0), dot(p1,p1), dot(p2, p2), dot(p3,p3)));
  p0 = p0 * norm.x;
  p1 = p1 * norm.y;
  p2 = p2 * norm.z;
  p3 = p3 * norm.w;

  var m = max(0.6 - vec4<f32>(dot(x0,x0), dot(x1,x1), dot(x2,x2), dot(x3,x3)), vec4<f32>(0.0));
  m = m * m;
  return 42.0 * dot( m*m, vec4<f32>( dot(p0,x0), dot(p1,x1), dot(p2,x2), dot(p3,x3) ) );
}

fn curlNoise(p: vec3<f32>) -> vec3<f32> {
    let e = 0.1;
    let dx = vec3<f32>(e, 0.0, 0.0);
    let dy = vec3<f32>(0.0, e, 0.0);
    let dz = vec3<f32>(0.0, 0.0, e);

    let p_x0 = snoise(p - dx);
    let p_x1 = snoise(p + dx);
    let p_y0 = snoise(p - dy);
    let p_y1 = snoise(p + dy);
    let p_z0 = snoise(p - dz);
    let p_z1 = snoise(p + dz);

    let x = p_y1 - p_y0 - p_z1 + p_z0;
    let y = p_z1 - p_z0 - p_x1 + p_x0;
    let z = p_x1 - p_x0 - p_y1 + p_y0;

    return normalize(vec3<f32>(x, y, z) / (2.0 * e));
}


@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dimensions = textureDimensions(readTexture);
    let coords = vec2<i32>(global_id.xy);
    if (coords.x >= i32(dimensions.x) || coords.y >= i32(dimensions.y)) { return; }

    let res = vec2<f32>(dimensions);
    // Base UVs
    let base_uv = vec2<f32>(coords) / res;
    let uv = base_uv * 2.0 - 1.0;

    // Core parameters from UI
    let flowSpeed = u.zoom_params.x;
    let threadDensity = u.zoom_params.y;
    let vortexStrength = u.zoom_params.z;
    let iridescence = u.zoom_params.w;

    // Audio reactivity
    let bass = extraBuffer[0];
    let audioPull = bass * 0.5;

    // Base 3D coordinate driven by time and uv
    let p = vec3<f32>(uv * 2.0, u.config.x * flowSpeed * 0.1);

    // Interaction logic
    var divergence = p;
    if (u.zoom_config.w > 0.0) {
        let mouseDist = distance(uv, u.zoom_config.yz * 2.0 - 1.0);
        let pull = exp(-mouseDist * 4.0) * vortexStrength;
        divergence += pull * normalize(vec3<f32>(uv - (u.zoom_config.yz * 2.0 - 1.0), 0.0));
    }

    // Audio attraction to center
    divergence -= normalize(vec3<f32>(uv, 0.0)) * audioPull;


    // Evaluate silk field
    let field = curlNoise(divergence * threadDensity);

    // Structural color
    let tension = length(field);
    let color = palette(tension * 0.5 + iridescence + u.config.x * 0.05);

    // Additive temporal blending
    let past = textureSampleLevel(readTexture, non_filtering_sampler, base_uv, 0.0).rgb;
    let finalColor = mix(past, color * tension, 0.05);

    textureStore(writeTexture, coords, vec4<f32>(finalColor, 1.0));
}
