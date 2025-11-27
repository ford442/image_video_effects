@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

@group(0) @binding(3) var<uniform> u: Uniforms;

// Noise functions borrowed for swirl effect
fn hash2(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn noise2D(p: vec2<f32>) -> vec2<f32> {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  let a = hash2(i);
  let b = hash2(i + vec2<f32>(1.0, 0.0));
  let c = hash2(i + vec2<f32>(0.0, 1.0));
  let d = hash2(i + vec2<f32>(1.0, 1.0));
  let h = mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
  return vec2<f32>(cos(h * 6.283), sin(h * 6.283));
}

fn flowPattern(p: vec2<f32>, time: f32) -> vec2<f32> {
  var flow = vec2<f32>(0.0);
  var amplitude = 1.0;
  var frequency = 1.0;
  for (var i = 0; i < 3; i++) {
    flow += noise2D(p * frequency + time * 0.1) * amplitude;
    amplitude *= 0.5;
    frequency *= 2.0;
  }
  return flow;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let currentTime = u.config.x;

  // --- Oil Swirl Logic ---
  // Continuous slow movement
  let time = currentTime * 0.05;
  let noiseuv = uv * 3.0;
  let flow = flowPattern(noiseuv, time);
  let ambientDisplacement = flow * 0.01;

  // --- Mouse Ripples ---
  var mouseDisplacement = vec2<f32>(0.0, 0.0);
  let rippleCount = u32(u.config.y);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let rippleData = u.ripples[i];
    let timeSinceClick = currentTime - rippleData.z;
    if (timeSinceClick > 0.0 && timeSinceClick < 3.0) {
      let direction_vec = uv - rippleData.xy;
      let dist = length(direction_vec);
      if (dist > 0.0001) {
        // Stir the oil
        let stir_speed = 1.5;
        // Vortex-like stir
        let stir = vec2<f32>(-direction_vec.y, direction_vec.x); // Tangent
        let wave = sin(dist * 10.0 - timeSinceClick * stir_speed);
        let attenuation = 1.0 - smoothstep(0.0, 1.0, timeSinceClick / 3.0);
        mouseDisplacement += stir * wave * 0.02 * attenuation;
      }
    }
  }

  let totalDisplacement = ambientDisplacement + mouseDisplacement;
  let displacedUV = uv + totalDisplacement;

  // Sample color
  let color = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0);

  // Add interference pattern (oil slick colors)
  // Based on noise/displacement magnitude
  let slick = length(totalDisplacement) * 10.0;
  let interference = 0.5 + 0.5 * cos(slick + vec3<f32>(0.0, 2.0, 4.0)); // Rainbow bands

  // Mix
  let finalColor = mix(color.rgb, interference, 0.1);

  textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));

  // Pass through depth
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
