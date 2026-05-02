// ═══════════════════════════════════════════════════════════════════
//  Pixel Depth Sort
//  Category: image
//  Features: mouse-driven, depth-aware
//  Complexity: Medium
//  Chunks From: pixel-depth-sort.wgsl
//  Created: 2026-05-02
//  By: Visualist
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

fn srgbToLinear(c: vec3<f32>) -> vec3<f32> {
  return pow(c, vec3<f32>(2.2));
}

fn linearToSrgb(c: vec3<f32>) -> vec3<f32> {
  return pow(c, vec3<f32>(1.0 / 2.2));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = vec3<f32>(2.51);
  let b = vec3<f32>(0.03);
  let c = vec3<f32>(2.43);
  let d = vec3<f32>(0.59);
  let e = vec3<f32>(0.14);
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn getLuma(color: vec3<f32>) -> f32 {
  return dot(color, vec3<f32>(0.299, 0.587, 0.114));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let dims = vec2<i32>(textureDimensions(writeTexture));
  if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) {
    return;
  }
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(coord) / vec2<f32>(dims);

  let mouse = u.zoom_config.yz;

  // Params
  let depth_scale = mix(0.0, 0.25, u.zoom_params.x);
  let atmos = u.zoom_params.y;
  let quality = u.zoom_params.z;
  let rim_power = u.zoom_params.w;

  let num_layers = mix(12.0, 80.0, quality);

  let tilt = vec2<f32>(0.5 - mouse.x, 0.5 - mouse.y);

  // Depth-aware displacement
  let sceneDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let view_vec = tilt * depth_scale * (0.5 + sceneDepth);

  // Atmospheric palettes
  let fogDeep = vec3<f32>(0.12, 0.22, 0.42);
  let fogNear = vec3<f32>(0.55, 0.38, 0.22);
  let rimColor = vec3<f32>(1.4, 0.95, 0.55);
  let skyTint = vec3<f32>(0.08, 0.14, 0.28);

  var final_color = vec3<f32>(0.0);
  var found = false;

  for (var i = 0.0; i <= 1.0; i += 1.0 / num_layers) {
    let layer_height = i;
    let offset = view_vec * layer_height;
    let sample_uv = uv + offset;

    if (all(sample_uv >= vec2<f32>(0.0)) && all(sample_uv <= vec2<f32>(1.0))) {
      let samp = textureSampleLevel(readTexture, u_sampler, sample_uv, 0.0).rgb;
      let luma = getLuma(samp);

      if (luma >= layer_height) {
        var lit = srgbToLinear(samp);

        // Edge-proximity rim specular
        let edge = luma - layer_height;
        let edgeMask = 1.0 - smoothstep(0.0, mix(0.02, 0.18, rim_power), edge);
        let rim = edgeMask * rimColor * rim_power * 4.0;
        lit += rim;

        // Soft self-shadow
        let shadow = 1.0 - atmos * 0.35 * (1.0 - smoothstep(0.0, 0.05, edge));
        lit *= shadow;

        // Layered atmospheric fog
        let fogColor = mix(fogDeep, fogNear, layer_height);
        let fogAmt = (1.0 - layer_height) * atmos * 0.6;
        lit = mix(fogColor, lit, exp(-fogAmt * 2.0));

        final_color = lit;
        found = true;
      } else if (!found) {
        let scatter = mix(fogDeep, fogNear, layer_height) * 0.05 * atmos;
        final_color += scatter * (1.0 / num_layers);
      }
    }
  }

  // Global atmospheric haze
  if (found) {
    let haze = exp(-atmos * 0.5);
    final_color = mix(skyTint * 0.35, final_color, haze);
  }

  // ACES tone mapping + gamma
  final_color = acesToneMap(final_color);
  final_color = linearToSrgb(final_color);

  textureStore(writeTexture, coord, vec4<f32>(final_color, 1.0));

  // Depth with atmospheric attenuation
  let outDepth = sceneDepth * (1.0 - atmos * 0.2);
  textureStore(writeDepthTexture, coord, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
}
