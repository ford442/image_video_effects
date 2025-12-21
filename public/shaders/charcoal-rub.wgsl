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

// Simple hash for noise
fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn noise(x: vec2<f32>) -> f32 {
    let i = floor(x);
    let f = fract(x);
    let a = hash12(i);
    let b = hash12(i + vec2<f32>(1.0, 0.0));
    let c = hash12(i + vec2<f32>(0.0, 1.0));
    let d = hash12(i + vec2<f32>(1.0, 1.0));
    let u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;

  // Params
  let hardness = mix(0.1, 0.9, u.zoom_params.x); // How sharp the reveal edge is
  let textureScale = mix(10.0, 100.0, u.zoom_params.y); // Paper texture scale
  let revealRate = mix(0.01, 0.2, u.zoom_params.z); // How fast you rub
  let fadeSpeed = mix(0.0, 0.05, u.zoom_params.w); // How fast it fades back

  let mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w; // 1.0 if down

  // Aspect ratio correction for mouse distance
  let aspect = resolution.x / resolution.y;
  let mouse_aspect = vec2<f32>(mouse.x * aspect, mouse.y);
  let uv_aspect = vec2<f32>(uv.x * aspect, uv.y);

  let dist = distance(uv_aspect, mouse_aspect);

  // Read previous state (reveal mask is in R channel)
  var state = textureLoad(dataTextureC, vec2<i32>(global_id.xy), 0).r;

  // Apply fading
  state = max(0.0, state - fadeSpeed);

  // Apply rubbing
  if (mouseDown > 0.5) {
      let brushRadius = 0.1;
      let brushSoftness = 0.5;
      let brushVal = 1.0 - smoothstep(brushRadius * (1.0 - brushSoftness), brushRadius, dist);

      // Add noise to brush for "rubbing" feel
      let brushNoise = noise(uv * textureScale + u.config.x * 10.0);

      state = min(1.0, state + brushVal * revealRate * (0.5 + 0.5 * brushNoise));
  }

  // Store state
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(state, 0.0, 0.0, 1.0));

  // Render
  // 1. Generate paper texture
  let paperNoise = fbm(uv * textureScale);
  let paperColor = vec3<f32>(0.95, 0.95, 0.9) * (0.8 + 0.2 * paperNoise); // Off-white paper

  // 2. Read actual image
  let imgColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

  // 3. Charcoal effect: Image becomes grayscale and high contrast
  let luma = dot(imgColor, vec3<f32>(0.299, 0.587, 0.114));
  let charcoalColor = vec3<f32>(smoothstep(0.8, 0.2, luma)); // Invert luma for charcoal darkness
  // Actually, let's keep it looking like the image but "sketchy"
  // Let's mix between paper and image based on state

  // Modulate state by paper texture to make the reveal grainy
  let revealMask = smoothstep(1.0 - hardness, 1.0, state * (0.5 + 0.5 * paperNoise));

  let finalColor = mix(paperColor, imgColor * (0.5 + 0.5 * paperNoise), revealMask);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, 1.0));
}
