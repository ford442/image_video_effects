// ═══════════════════════════════════════════════════════════════════
//  Coral Reef Colony
//  Category: generative
//  Features: coral, organic, generative, audio-reactive, mouse-interactive, semantic-alpha, simulation-like
//  Complexity: Very High
//  Created: 2026-05-30
//  Updated: 2026-06-01
//  By: Kimi Agent (4-Agent Swarm Upgrade)
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

fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

fn fbm(p: vec2<f32>, time: f32) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var pp = p;
  for (var i: i32 = 0; i < 5; i = i + 1) {
    let h = hash21(pp + vec2<f32>(f32(i) * 7.3, time * 0.01));
    v += a * h;
    pp = pp * 2.1 + vec2<f32>(3.2, 1.7);
    a *= 0.5;
  }
  return v;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = x * (x * 0.15 + 0.05) + 0.004;
  let b = x * (x * 0.15 + 0.50) + 0.06;
  return clamp(a / b - 0.0033, vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let growth = u.zoom_params.x;
  let polypSize = u.zoom_params.y;
  let colorVariety = u.zoom_params.z;
  let mouseAttraction = u.zoom_params.w;

  let mouse = u.zoom_config.yz;
  let depth = smoothstep(0.0, 1.0, uv.y);

  let nutrient = growth * (0.6 + bass * 0.8);
  let current = vec2<f32>(sin(time * 0.2 + mids * 2.0), cos(time * 0.15 - mids * 1.5)) * 0.3;
  let spawnPulse = step(0.82, treble);

  let colonyUV = uv * 6.0 + current * time * 0.08;
  let branchNoise = fbm(colonyUV, time);
  let branchAngle = branchNoise * 6.2831;

  let nodePos = fract(colonyUV) - 0.5;
  let rotNode = vec2<f32>(
    nodePos.x * cos(branchAngle) - nodePos.y * sin(branchAngle),
    nodePos.x * sin(branchAngle) + nodePos.y * cos(branchAngle)
  );

  let branch = smoothstep(0.45, 0.12, abs(rotNode.x)) * smoothstep(0.5, 0.0, abs(rotNode.y));
  let dla = fbm(uv * 12.0 + hash21(floor(colonyUV)) * 3.0, time * 0.5);
  let dlaBranch = smoothstep(0.35, 0.7, dla) * nutrient;

  let mousePull = (1.0 - smoothstep(0.0, 0.55, length(uv - mouse))) * mouseAttraction;
  let coralDensity = clamp((branch * 0.7 + dlaBranch * 0.5 + spawnPulse * 0.3) * nutrient + mousePull, 0.0, 1.0);

  let polypGrid = fract(uv * (18.0 + polypSize * 14.0)) - 0.5;
  let polypDist = length(polypGrid);
  let polyp = smoothstep(polypSize * 0.5, polypSize * 0.08, polypDist) * coralDensity;

  let caustics = abs(sin(uv.x * 40.0 + time * 0.6) + sin(uv.y * 35.0 - time * 0.4)) * 0.5;
  let causticLight = caustics * (0.15 + depth * 0.25) * (1.0 + treble * 0.5);

  let hue = fract(uv.x * 0.35 + uv.y * 0.25 + time * 0.015 + colorVariety * 0.6 + mids * 0.12);
  var coral = vec3<f32>(
    0.5 + 0.5 * sin(hue * 6.28),
    0.25 + 0.55 * sin(hue * 6.28 + 2.2),
    0.35 + 0.65 * sin(hue * 6.28 + 4.1)
  );
  coral = mix(coral, vec3<f32>(0.1, 0.9, 0.7), spawnPulse * 0.4);

  let sss = smoothstep(0.0, 0.4, coralDensity) * 0.35;
  var color = coral * (coralDensity * 0.8 + polyp * 1.4 + sss);

  let bloom = polyp * vec3<f32>(0.6, 1.0, 0.8) * (0.5 + bass * 0.6);
  color += bloom * 0.6;
  color += vec3<f32>(0.1, 0.3, 0.5) * causticLight;

  let waterTint = vec3<f32>(0.02, 0.08, 0.14);
  let depthAtten = mix(0.25, 0.85, depth);
  color = mix(waterTint * depthAtten, color, clamp(coralDensity + polyp * 0.5, 0.0, 1.0));

  color = acesToneMap(color * (1.0 + bass * 0.25));

  let biolum = polyp * (0.4 + bass * 0.5);
  let semantic_alpha = clamp(coralDensity * biolum * depthAtten, 0.2, 0.98);

  textureStore(writeTexture, global_id.xy, vec4<f32>(color, semantic_alpha));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(coralDensity * depthAtten, 0.0, 0.0, 0.0));
}
