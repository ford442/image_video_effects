// Julia Set Classic — escape-time fractal with orbit traps and pointer-controlled C
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
const TAU: f32 = 6.28318530718;
fn palette(t: f32) -> vec3<f32> { return vec3<f32>(0.5)+vec3<f32>(0.5)*cos(TAU*(vec3<f32>(t)+vec3<f32>(0.0,0.31,0.67))); }
fn acesToneMap(x: vec3<f32>) -> vec3<f32> { return clamp((x*(2.51*x+0.03))/(x*(2.43*x+0.59)+0.14),vec3<f32>(0.0),vec3<f32>(1.0)); }

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let res = u.config.zw;
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }
  let uv01 = (vec2<f32>(pixel) + vec2<f32>(0.5)) / res;
  let aspect = res.x / res.y;
  let screenP = (uv01 - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0);
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let zoom = max(u.zoom_params.z, 0.05);
  let iterations = i32(clamp(round(u.zoom_params.w), 8.0, 160.0));
  let held = clamp(u.zoom_config.w, 0.0, 1.0);
  let mouseC = (u.zoom_config.yz - vec2<f32>(0.5)) * vec2<f32>(2.4, -2.4);
  let baseC = vec2<f32>(u.zoom_params.x, u.zoom_params.y);
  let c = mix(baseC + vec2<f32>(sin(time * 0.09), cos(time * 0.07)) * mids * 0.006, mouseC, held * 0.82);

  var clickWarp = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var ri = 0u; ri < rippleCount; ri++) {
    let ripple = u.ripples[ri];
    let age = time - ripple.z;
    if (age > 0.0 && age < 3.0) {
      let center = (ripple.xy - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0);
      clickWarp += exp(-abs(distance(screenP, center) - age * 0.2) * 68.0) * exp(-age * 1.35);
    }
  }
  var z = screenP * (2.45 / zoom) + vec2<f32>(clickWarp * 0.015, -clickWarp * 0.01);
  var escaped = f32(iterations);
  var trap = 10.0;
  var orbit = 0.0;
  for (var i = 0; i < 160; i++) {
    if (i >= iterations) { break; }
    let x = z.x * z.x - z.y * z.y + c.x;
    let y = 2.0 * z.x * z.y + c.y;
    z = vec2<f32>(x, y);
    trap = min(trap, min(abs(z.x), abs(length(z) - 0.5)));
    orbit += exp(-abs(length(z) - 1.0) * 8.0) / f32(iterations);
    if (dot(z, z) > 256.0) { escaped = f32(i); break; }
  }
  let escapedMask = select(0.0, 1.0, escaped < f32(iterations));
  let smoothIter = escaped - log2(max(log2(max(dot(z, z), 1.0001)), 0.0001));
  let normalized = clamp(smoothIter / f32(iterations), 0.0, 1.0);
  let trapGlow = exp(-trap * (45.0 + treble * 24.0));
  let interior = 1.0 - escapedMask;
  var raw = palette(normalized * 3.2 + time * 0.012 + mids * 0.08) * escapedMask * (0.25 + normalized * 1.5 + bass * 0.2);
  raw += palette(trapGlow * 0.3 + 0.37) * trapGlow * (0.5 + treble * 0.9);
  raw += vec3<f32>(0.04, 0.08, 0.16) * interior * (0.7 + orbit * 0.5);
  raw += vec3<f32>(1.1, 0.45, 1.4) * clickWarp * 0.48;
  let prev = textureLoad(dataTextureC, pixel, 0);
  raw = clamp(mix(prev.rgb * 0.935, raw, 0.32 + bass * 0.025), vec3<f32>(0.0), vec3<f32>(7.0));
  let alpha = clamp(0.04 + escapedMask * normalized * 0.58 + trapGlow * 0.3 + interior * 0.16 + clickWarp * 0.12, 0.04, 0.98);
  let depth = clamp(interior * 0.88 + trapGlow * 0.45 + normalized * 0.25, 0.0, 1.0);
  textureStore(dataTextureA, pixel, vec4<f32>(raw, alpha));
  textureStore(writeTexture, pixel, vec4<f32>(acesToneMap(raw * 1.1), alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
