// ═══════════════════════════════════════════════════════════════════
//  Neon Quantum Lattice
//  Category: geometric
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: Very High
//  Chunks From: neon-quantum-lattice
//  Upgraded: 2026-05-30
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

fn aces_tonemap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn penrose_dist(p: vec2<f32>, scale: f32) -> f32 {
  let a1 = vec2<f32>(cos(0.0), sin(0.0));
  let a2 = vec2<f32>(cos(2.094), sin(2.094));
  let a3 = vec2<f32>(cos(4.189), sin(4.189));
  let a4 = vec2<f32>(cos(1.047), sin(1.047));
  let a5 = vec2<f32>(cos(3.142), sin(3.142));
  let s = p * scale;
  let d1 = abs(fract(dot(s, a1)) - 0.5);
  let d2 = abs(fract(dot(s, a2)) - 0.5);
  let d3 = abs(fract(dot(s, a3)) - 0.5);
  let d4 = abs(fract(dot(s, a4)) - 0.5);
  let d5 = abs(fract(dot(s, a5)) - 0.5);
  let m = min(min(min(min(d1, d2), d3), d4), d5);
  return m / scale;
}

fn tile_color(uv: vec2<f32>, t: f32, bass: f32) -> vec3<f32> {
  let phi = 1.6180339887;
  let pattern = sin(uv.x * phi * 3.0 + t * 0.2) * cos(uv.y * phi * 2.0 - t * 0.3);
  let warm = vec3<f32>(0.9, 0.5, 0.2);
  let cool = vec3<f32>(0.2, 0.4, 0.9);
  return mix(cool, warm, pattern * 0.5 + 0.5) * (0.8 + bass * 0.3);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = u.config.zw;
    if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

    let uv = vec2<f32>(gid.xy) / dims;
    let t = u.config.x;
    let mouse = u.zoom_config.yz;
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    let inflation = mix(8.0, 40.0, u.zoom_params.x) * (1.0 + bass * 0.5);
    let glowWidth = mix(0.003, 0.02, u.zoom_params.y) * (1.0 + treble * 0.3);
    let parallax = u.zoom_params.z * 0.05;
    let brightness = u.zoom_params.w;

    let layer1UV = uv + depth * parallax;
    let layer2UV = uv - depth * parallax * 0.5;
    let layer3UV = uv + vec2<f32>(sin(t * 0.1), cos(t * 0.1)) * parallax * 0.3;

    let d1 = penrose_dist(layer1UV - mouse * 0.1, inflation);
    let d2 = penrose_dist(layer2UV + mouse * 0.05, inflation * 1.618);
    let d3 = penrose_dist(layer3UV, inflation * 2.618);

    let edge1 = 1.0 - smoothstep(0.0, glowWidth, d1);
    let edge2 = 1.0 - smoothstep(0.0, glowWidth * 1.3, d2);
    let edge3 = 1.0 - smoothstep(0.0, glowWidth * 1.6, d3);
    let edgeConfidence = max(max(edge1, edge2 * 0.7), edge3 * 0.4);

    let vertexGlow = pow(edge1 * edge2, 2.0) * 4.0 * (1.0 + mids);
    let vertexGlow2 = pow(edge2 * edge3, 2.0) * 3.0 * (1.0 + treble * 0.5);

    let mouseDist = length(uv - mouse);
    let uncertainty = 1.0 - smoothstep(0.0, 0.35, mouseDist);
    let quantumNoise = fract(sin(dot(uv, vec2<f32>(12.9898, 78.233)) + t * 3.0) * 43758.5453);
    let quantumZone = uncertainty * quantumNoise * 0.25;

    let tileFill = smoothstep(0.0, glowWidth * 3.0, d1) * (1.0 - edge1);
    let metallic_base = tile_color(layer1UV, t, bass) * tileFill;
    var metallic = metallic_base + vec3<f32>(0.3, 0.1, 0.4) * quantumZone;

    let neonRim = vec3<f32>(0.2, 0.9, 1.0) * edge1 * (1.0 + bass * 0.6);
    let neonInner = vec3<f32>(1.0, 0.3, 0.7) * edge2 * (1.0 + mids * 0.5);
    let neonDeep = vec3<f32>(0.5, 0.2, 1.0) * edge3 * (1.0 + treble * 0.3);
    var rgb = metallic + neonRim + neonInner * 0.6 + neonDeep * 0.3;

    rgb += vec3<f32>(1.0, 0.9, 0.5) * (vertexGlow + vertexGlow2) * 0.2;
    rgb += vec3<f32>(0.1, 0.4, 1.0) * quantumZone * edgeConfidence;

    rgb = aces_tonemap(rgb * (0.8 + brightness * 0.5));

    let alpha = clamp(edgeConfidence * (0.7 + depth * 0.3) + (vertexGlow + vertexGlow2) * 0.1 + uncertainty * 0.1, 0.0, 1.0);

    let finalColor = vec4<f32>(rgb, alpha);
    textureStore(writeTexture, gid.xy, finalColor);
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth + edgeConfidence * 0.05, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, gid.xy, finalColor);
}
