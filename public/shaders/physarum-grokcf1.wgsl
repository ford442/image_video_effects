// Physarum Polycephalum (Slime Mold) grokcf1 - Advanced Simulation
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // trail_map
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>; // agent storage
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>; // agents
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// ✨ grokcf1 UPGRADE: Agent struct
struct Agent {
  pos: vec2<f32>,
  angle: f32,
  p_type: f32, // Personality type
};

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

@compute @workgroup_size(256, 1, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let idx = gid.x;
  if (idx * 4u + 3u >= arrayLength(&extraBuffer)) { return; }

  var agent: Agent;
  agent.pos = vec2<f32>(extraBuffer[idx * 4u + 0u], extraBuffer[idx * 4u + 1u]);
  agent.angle = extraBuffer[idx * 4u + 2u];
  agent.p_type = extraBuffer[idx * 4u + 3u];

  let tex_size = vec2<f32>(textureDimensions(readTexture));
  let time = u.config.x;
  
  // ✨ grokcf1 UPGRADE: Sense-and-turn logic
  let sensor_angle = 0.5; // radians
  let sensor_dist = 5.0 / tex_size.x;
  let dir = vec2<f32>(cos(agent.angle), sin(agent.angle));
  
  let f_pos = agent.pos + dir * sensor_dist;
  let l_pos = agent.pos + vec2<f32>(cos(agent.angle - sensor_angle), sin(agent.angle - sensor_angle)) * sensor_dist;
  let r_pos = agent.pos + vec2<f32>(cos(agent.angle + sensor_angle), sin(agent.angle + sensor_angle)) * sensor_dist;
  
  let f_sense = textureSampleLevel(dataTextureC, non_filtering_sampler, f_pos, 0.0).a;
  let l_sense = textureSampleLevel(dataTextureC, non_filtering_sampler, l_pos, 0.0).a;
  let r_sense = textureSampleLevel(dataTextureC, non_filtering_sampler, r_pos, 0.0).a;
  
  // Steer away from other trails
  if (f_sense > l_sense && f_sense > r_sense) {
    // No change
  } else if (l_sense > r_sense) {
    agent.angle -= 0.2;
  } else if (r_sense > l_sense) {
    agent.angle += 0.2;
  }
  
  // Random turn
  if (hash(agent.pos + time) > 0.95) {
      agent.angle += (hash(agent.pos - time) - 0.5) * 2.0;
  }

  // ✨ grokcf1 UPGRADE: Nutrient interaction
  let nutrient_color = textureSampleLevel(readTexture, u_sampler, agent.pos, 0.0).rgb;
  let nutrient_value = length(nutrient_color);

  // Move faster in nutrient-rich areas
  let speed = 0.001 + nutrient_value * 0.002;
  agent.pos += vec2<f32>(cos(agent.angle), sin(agent.angle)) * speed;
  
  // Wrap around screen edges
  agent.pos = fract(agent.pos);

  // Deposit trail
  let coord = vec2<u32>(agent.pos * tex_size);
  let trail_color = mix(vec3<f32>(0.9, 0.9, 0.8), nutrient_color, 0.7);
  
  // ✨ grokcf1 UPGRADE: Trail decay and blending
  let current_trail = textureLoad(dataTextureC, vec2<i32>(coord), 0);
  let new_trail = mix(current_trail.rgb, trail_color, 0.1);
  let decayed_trail = max(current_trail.rgb - 0.001, vec3<f32>(0.0));
  textureStore(dataTextureA, vec2<i32>(coord), vec4<f32>(mix(decayed_trail, new_trail, 0.5), 1.0));
  
  // Write back agent data
  extraBuffer[idx * 4u + 0u] = agent.pos.x;
  extraBuffer[idx * 4u + 1u] = agent.pos.y;
  extraBuffer[idx * 4u + 2u] = agent.angle;
  extraBuffer[idx * 4u + 3u] = agent.p_type;

  // ✨ grokcf1 UPGRADE: Pulsing effect
  let pulse = sin(time * 5.0 + agent.p_type * 6.28) * 0.5 + 0.5;
  if (pulse > 0.9) {
    textureStore(writeTexture, vec2<i32>(coord), vec4<f32>(1.0, 1.0, 1.0, 1.0));
  }
}
