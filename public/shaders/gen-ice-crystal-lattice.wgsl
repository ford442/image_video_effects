// Ice Crystal Lattice — hexagonal branching frost and fracture fronts
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
  config: vec4<f32>, zoom_config: vec4<f32>, zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

const TAU: f32 = 6.28318530718;

fn latticeLine(p: vec2<f32>, normal: vec2<f32>, density: f32, width: f32) -> f32 {
  let d = abs(fract(dot(p, normal) * density + 0.5) - 0.5);
  return 1.0 - smoothstep(width, width * 2.4, d);
}

fn palette(t: f32) -> vec3<f32> {
  return vec3<f32>(0.48) + vec3<f32>(0.52) * cos(TAU * (vec3<f32>(t) + vec3<f32>(0.56, 0.66, 0.82)));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let res = u.config.zw;
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }
  let uv01 = (vec2<f32>(pixel) + vec2<f32>(0.5)) / res;
  let aspect = res.x / res.y;
  let p = (uv01 - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0);
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let density = mix(5.0, 22.0, clamp(u.zoom_params.x, 0.0, 1.0));
  let branching = clamp(u.zoom_params.y, 0.0, 1.0);
  let growthSpeed = mix(0.08, 0.55, clamp(u.zoom_params.z, 0.0, 1.0));
  let frostGlow = mix(0.35, 2.8, clamp(u.zoom_params.w, 0.0, 1.0));

  let n0 = vec2<f32>(1.0, 0.0);
  let n1 = vec2<f32>(0.5, 0.8660254);
  let n2 = vec2<f32>(-0.5, 0.8660254);
  let width = mix(0.055, 0.018, clamp(u.zoom_params.x, 0.0, 1.0));
  let l0 = latticeLine(p, n0, density, width);
  let l1 = latticeLine(p, n1, density, width);
  let l2 = latticeLine(p, n2, density, width);
  let hexWeb = max(l0, max(l1, l2));
  let radius = length(p);
  let angle = atan2(p.y, p.x);
  let branchNeedles = pow(0.5 + 0.5 * cos(angle * 6.0 + sin(radius * density * 0.7) * branching * 2.2), 8.0);
  let growthFront = 1.0 - smoothstep(0.0, 0.085, abs(radius - fract(time * growthSpeed + bass * 0.06) * 0.9));

  let mouse = (u.zoom_config.yz - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0);
  let held = clamp(u.zoom_config.w, 0.0, 1.0);
  let nucleation = exp(-distance(p, mouse) * (10.0 + density * 0.45)) * held;
  let localBranches = pow(0.5 + 0.5 * cos(atan2(p.y - mouse.y, p.x - mouse.x) * 6.0), 10.0) * nucleation;

  var fracture = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var ri = 0u; ri < rippleCount; ri++) {
    let ripple = u.ripples[ri];
    let age = time - ripple.z;
    if (age > 0.0 && age < 3.4) {
      let center = (ripple.xy - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0);
      let delta = p - center;
      let front = abs(length(delta) - age * (0.18 + growthSpeed * 0.3));
      let cracks = pow(0.5 + 0.5 * cos(atan2(delta.y, delta.x) * 12.0 + f32(ri)), 14.0);
      fracture += exp(-front * 82.0) * (0.3 + cracks * 0.7) * exp(-age * 1.2);
    }
  }

  let crystal = clamp(hexWeb * (0.35 + branchNeedles * branching) + growthFront * hexWeb * 0.55 + nucleation + localBranches + fracture, 0.0, 2.0);
  let fresnelFrost = pow(clamp(hexWeb * 0.65 + branchNeedles * 0.25 + fracture * 0.5, 0.0, 1.0), 1.5);
  var raw = vec3<f32>(0.008, 0.025, 0.05);
  raw += palette(radius * 0.25 + mids * 0.08) * crystal * (0.45 + frostGlow * 0.7);
  raw += vec3<f32>(0.7 + bass * 0.2, 1.15 + mids * 0.28, 1.7 + treble * 0.6) * fresnelFrost * frostGlow;
  let prev = textureLoad(dataTextureC, pixel, 0);
  raw = clamp(mix(prev.rgb * 0.945, raw, 0.24 + growthSpeed * 0.12), vec3<f32>(0.0), vec3<f32>(7.0));
  let alpha = clamp(0.03 + crystal * 0.62 + fresnelFrost * 0.22, 0.03, 0.98);
  let depth = clamp(crystal * 0.55 + fresnelFrost * 0.32, 0.0, 1.0);
  textureStore(dataTextureA, pixel, vec4<f32>(raw, alpha));
  textureStore(writeTexture, pixel, vec4<f32>(acesToneMap(raw * 1.08), alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
