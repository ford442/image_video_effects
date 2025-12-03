// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // Use for persistence/trail history
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>; // Or generic object data
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

// Parameters Mapping:
// zoom_params.x = Rain Speed
// zoom_params.y = Rain Density
// zoom_params.z = Wind Strength/Direction
// zoom_params.w = Splash/Flow Strength

fn hash12(p: vec2<f32>) -> f32 {
    var p3  = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash13(p: vec3<f32>) -> f32 {
    var p3  = fract(p * .1031);
    p3 += dot(p3, p3.zyx + 31.32);
    return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash12(i + vec2<f32>(0.0, 0.0)),
                   hash12(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash12(i + vec2<f32>(0.0, 1.0)),
                   hash12(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn rain_layer(uv: vec2<f32>, seed: f32, speed: f32, density: f32, wind: f32, time: f32) -> f32 {
    // Skew UV for wind
    let skewed_uv = vec2<f32>(uv.x - uv.y * wind * 0.5, uv.y);

    // Animate
    let t = time * speed;
    let st = skewed_uv * vec2<f32>(50.0 + seed * 20.0, 5.0 + seed * 2.0); // X is density, Y is streak length
    let pos = st + vec2<f32>(0.0, t);

    let cell = floor(pos);
    let f = fract(pos);

    let rand = hash12(cell + seed);

    // Density check
    if (rand > density) {
        return 0.0;
    }

    // Draw streak
    // Simple vertical gradient in cell
    let streak = smoothstep(0.0, 1.0, 1.0 - f.y) * smoothstep(0.0, 0.1, f.y);
    // Fade x
    let x_fade = smoothstep(0.0, 0.2, f.x) * smoothstep(1.0, 0.8, f.x);

    return streak * x_fade;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;

  // Parameters
  let rain_speed = max(0.01, u.zoom_params.x * 20.0);
  let rain_density = clamp(u.zoom_params.y * 0.5, 0.0, 1.0); // 0 to 1
  let wind = u.zoom_params.z - 2.0; // Center at 0 (range -2 to 2 typically)
  let flow_strength = u.zoom_params.w;

  // Sample Depth
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  // --- Rain Layers ---
  var rain_acc = 0.0;

  // Layer 1: Far (z ~ 0.2)
  if (depth < 0.25) { // Only draw if object is further than rain
      rain_acc += rain_layer(uv, 12.34, rain_speed * 0.8, rain_density, wind, time) * 0.5;
  }

  // Layer 2: Mid (z ~ 0.5)
  if (depth < 0.55) {
      rain_acc += rain_layer(uv, 56.78, rain_speed * 1.0, rain_density, wind, time) * 0.7;
  }

  // Layer 3: Near (z ~ 0.8)
  if (depth < 0.85) {
       rain_acc += rain_layer(uv, 90.12, rain_speed * 1.2, rain_density, wind, time);
  }

  // --- Splashes ---
  // Visualize hits where rain "intersects" depth surface
  // We approximate this by high frequency noise at specific depth bands or just random hits
  var splash = 0.0;
  if (flow_strength > 0.05) {
      // Random splashes
      let splash_uv = uv * vec2<f32>(50.0, 50.0);
      let splash_noise = hash13(vec3<f32>(splash_uv, time * 10.0));
      // Mask by density
      if (splash_noise > (1.0 - rain_density * 0.2)) {
          // Check if this pixel is a "surface" that faces up?
          // Or just randomly on surface
          if (depth > 0.1) {
              splash += 0.5 * flow_strength;
          }
      }
  }

  // --- Flow / Wetness ---
  var flow = 0.0;
  if (flow_strength > 0.0) {
      // Calculate Gradient of depth to distort flow
      // We need neighbors. Since this is compute, we can sample neighbors.
      let texel = 1.0 / resolution;
      let d_up = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(0.0, texel.y), 0.0).r;
      let d_down = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, texel.y), 0.0).r;
      let d_left = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(texel.x, 0.0), 0.0).r;
      let d_right = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(texel.x, 0.0), 0.0).r;

      let grad = vec2<f32>(d_right - d_left, d_down - d_up) * 5.0;

      // Flow follows gravity (down) + gradient
      // If slope is steep, flow is faster/distorted

      let flow_uv = uv + vec2<f32>(0.0, -time * 0.2) + grad * 0.05;
      let flow_noise = noise(flow_uv * 20.0);

      // Wet trails
      flow = smoothstep(0.4, 0.6, flow_noise) * flow_strength * 0.3;

      // Mask flow by depth (less flow in far background)
      flow *= smoothstep(0.0, 0.2, depth);
  }

  // --- Combine ---
  let base_color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  // Rain is additive white/blue
  let rain_color = vec4<f32>(0.8, 0.9, 1.0, 1.0);

  var final_color = base_color + (rain_color * rain_acc * 0.5) + (rain_color * splash) + (rain_color * flow);

  // Output
  textureStore(writeTexture, global_id.xy, final_color);

  // Pass Depth
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
