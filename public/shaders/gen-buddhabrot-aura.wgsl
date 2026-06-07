// ═══════════════════════════════════════════════════════════════════
//  Buddhabrot Aura
//  Category: generative
//  Features: buddhabrot, fractal, generative, audio-reactive, mouse-interactive, semantic-alpha
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

fn hash22(p: vec2<f32>) -> vec2<f32> {
  let h = vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)));
  return fract(sin(h) * 43758.5453123);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = x * (x * 0.15 + 0.05) + 0.004;
  let b = x * (x * 0.15 + 0.50) + 0.06;
  return clamp(a / b - 0.0033, vec3<f32>(0.0), vec3<f32>(1.0));
}

fn orbitTrapColor(z: vec2<f32>, trapCenter: vec2<f32>) -> vec3<f32> {
  let d = length(z - trapCenter);
  let t = 1.0 / (1.0 + d * 3.0);
  return vec3<f32>(t * 1.2, t * t * 0.9, t * t * t * 1.4);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = (vec2<f32>(global_id.xy) - 0.5 * resolution) / resolution.y;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let orbitThreshold = u.zoom_params.x;
  let densityScale = u.zoom_params.y;
  let mouseZoom = u.zoom_params.z;
  let aura = u.zoom_params.w;

  let mouse = u.zoom_config.yz;
  let mouseC = (mouse - 0.5) * 2.2 * mouseZoom;
  let depth = smoothstep(0.0, 1.0, u.config.w / resolution.y);

  let baseIter = i32(20.0 + orbitThreshold * 120.0 + bass * 40.0);
  let scale = 2.0 + mouseZoom * 2.0;
  let center = uv * scale + mouseC;

  var density = 0.0;
  var escapeVel = 0.0;
  var orbitColor = vec3<f32>(0.0);
  var bloom = vec3<f32>(0.0);

  let samples = 4u;
  let h0 = hash22(vec2<f32>(f32(global_id.x), f32(global_id.y)) + fract(time) * 13.37);

  for (var s: u32 = 0u; s < samples; s = s + 1u) {
    let h = hash22(h0 + vec2<f32>(f32(s) * 1.618, f32(s) * 2.718));
    let offset = (h - 0.5) * 0.002;
    let c = center + offset;

    var z = vec2<f32>(0.0);
    var orbit = vec3<f32>(0.0);
    var pathLen = 0.0;

    for (var i: i32 = 0; i < baseIter; i = i + 1) {
      z = vec2<f32>(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y) + c;
      pathLen = pathLen + 1.0;
      let dist = dot(z, z);

      orbit += orbitTrapColor(z, vec2<f32>(0.35, 0.12));

      if (dist > 4.0) {
        escapeVel = escapeVel + 1.0;
        let esc = f32(i) / f32(baseIter);
        density += esc * (1.0 + bass * 0.5);
        bloom += orbit * esc * esc * (0.3 + treble * 0.4);
        break;
      }
    }
    orbitColor += orbit * (1.0 / f32(baseIter));
  }

  density = density / f32(samples);
  escapeVel = escapeVel / f32(samples);
  orbitColor = orbitColor / f32(samples);
  bloom = bloom / f32(samples);

  let dMap = density * densityScale * 3.0;
  let nebula = vec3<f32>(
    fract(dMap * 1.6 + mids * 0.25 + time * 0.02),
    fract(dMap * 1.05 + treble * 0.15),
    fract(dMap * 0.7 + bass * 0.12 + time * 0.015)
  );

  var color = mix(nebula, orbitColor, 0.35) * (0.5 + aura * 1.2);
  color += bloom * aura * 2.5;

  let centerGlow = length(uv - mouseC * 0.25);
  color += vec3<f32>(0.2, 0.15, 0.35) * smoothstep(0.9, 0.15, centerGlow) * aura * (0.6 + bass * 0.4);

  let chrOffset = density * densityScale * 0.012 * aura;
  let chrR = mix(color.r, color.r * 1.15, chrOffset * 8.0);
  let chrB = mix(color.b, color.b * 1.1, chrOffset * 6.0);
  color = vec3<f32>(chrR, color.g, chrB);

  color = acesToneMap(color * (1.0 + densityScale * 0.4));

  let semantic_alpha = clamp(density * escapeVel * (0.4 + depth * 0.6), 0.25, 0.98);

  textureStore(writeTexture, global_id.xy, vec4<f32>(color, semantic_alpha));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(density * 0.7, 0.0, 0.0, 0.0));
}
