struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 30>,
};

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

// Hash function
fn hash(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i + vec2<f32>(0.0, 0.0)), hash(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash(i + vec2<f32>(0.0, 1.0)), hash(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var shift = vec2<f32>(100.0);
    var rot = mat2x2<f32>(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
    var x = p;
    for (var i = 0; i < 5; i++) {
        v = v + a * noise(x);
        x = rot * x * 2.0 + shift;
        a = a * 0.5;
    }
    return v;
}

fn getLuma(color: vec3<f32>) -> f32 {
  return dot(color, vec3<f32>(0.299, 0.587, 0.114));
}

@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let dims = vec2<i32>(textureDimensions(writeTexture));
  if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) {
    return;
  }
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(coord) / vec2<f32>(dims);
  let aspect = f32(dims.x) / f32(dims.y);

  // Params
  let radius = mix(0.05, 0.5, u.zoom_params.x);
  let roughness = u.zoom_params.y; // Frequency of foil noise
  let relief = u.zoom_params.z; // Strength of image emboss
  let color_mix_amt = u.zoom_params.w;

  let mouse = u.zoom_config.yz;
  let mouse_aspect = vec2<f32>(mouse.x * aspect, mouse.y);
  let uv_aspect = vec2<f32>(uv.x * aspect, uv.y);

  let dist = distance(uv_aspect, mouse_aspect);
  let press_factor = smoothstep(radius, radius * 0.5, dist); // 1.0 at center, 0.0 outside

  // 1. Generate Foil Normal
  // High frequency noise
  let noise_freq = mix(10.0, 100.0, roughness);
  // Calculate noise gradient for normal
  let eps = 0.001;
  let n_val = fbm(uv * noise_freq);
  let n_x = fbm((uv + vec2<f32>(eps, 0.0)) * noise_freq) - n_val;
  let n_y = fbm((uv + vec2<f32>(0.0, eps)) * noise_freq) - n_val;

  var foil_normal = normalize(vec3<f32>(-n_x * 20.0, -n_y * 20.0, 1.0));

  // 2. Generate Image Relief Normal
  // Sample neighbors for Sobel
  let px = 1.0 / vec2<f32>(dims);
  let l_x1 = getLuma(textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(px.x, 0.0), 0.0).rgb);
  let l_x2 = getLuma(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(px.x, 0.0), 0.0).rgb);
  let l_y1 = getLuma(textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(0.0, px.y), 0.0).rgb);
  let l_y2 = getLuma(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, px.y), 0.0).rgb);

  let dx = (l_x1 - l_x2) * mix(1.0, 10.0, relief);
  let dy = (l_y1 - l_y2) * mix(1.0, 10.0, relief);

  let image_normal = normalize(vec3<f32>(dx, dy, 1.0));

  // 3. Mix Normals
  // Combine: Where pressed, we see Image Normal. Where not, Foil Normal.
  let final_normal = normalize(mix(foil_normal, image_normal, press_factor));

  // 4. Color
  let img_color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let foil_base = vec3<f32>(0.7, 0.7, 0.75); // Silver

  // If pressed, show more image color. If not, silver.
  let target_color = mix(foil_base, img_color, color_mix_amt);
  let final_albedo = mix(foil_base, target_color, press_factor);

  // 5. Lighting
  let light_dir = normalize(vec3<f32>(0.5, -0.5, 1.0));
  let view_dir = vec3<f32>(0.0, 0.0, 1.0);
  let half_dir = normalize(light_dir + view_dir);

  let NdotL = max(0.0, dot(final_normal, light_dir));
  let NdotH = max(0.0, dot(final_normal, half_dir));

  let spec_pow = mix(30.0, 10.0, press_factor);
  let spec = pow(NdotH, spec_pow) * 0.8;

  var col = final_albedo * (0.3 + 0.7 * NdotL) + vec3<f32>(spec);

  // Tone mapping / clamp
  col = clamp(col, vec3<f32>(0.0), vec3<f32>(1.0));

  textureStore(writeTexture, coord, vec4<f32>(col, 1.0));
}
