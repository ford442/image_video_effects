// ═══════════════════════════════════════════════════════════════════
//  Pixelate Blast v2
//  Category: distortion
//  Features: mouse-driven, audio-reactive, upgraded-rgba, voronoi-cells
//  Complexity: High
//  Chunks From: pixelate-blast, voronoi, domain-warp
//  Created: 2026-05-31
//  By: 4-Agent Shader Upgrade Swarm
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

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  let n = hash12(p);
  return vec2<f32>(n, hash12(p + vec2<f32>(1.0, 0.0)));
}

fn voronoi(p: vec2<f32>, time: f32) -> vec3<f32> {
  let n = floor(p);
  let f = fract(p);
  var md = 8.0;
  var md2 = 8.0;
  var closest = vec2<f32>(0.0);
  for (var j = -1; j <= 1; j = j + 1) {
    for (var i = -1; i <= 1; i = i + 1) {
      let g = vec2<f32>(f32(i), f32(j));
      let o = hash22(n + g) * 0.5 + 0.25;
      let anim = vec2<f32>(sin(time + hash12(n + g) * 6.28), cos(time + hash12(n + g + 1.0) * 6.28)) * 0.15;
      let r = g + o + anim - f;
      let d = dot(r, r);
      if (d < md) {
        md2 = md;
        md = d;
        closest = n + g + o;
      } else if (d < md2) {
        md2 = d;
      }
    }
  }
  return vec3<f32>(sqrt(md), sqrt(md2), hash12(closest));
}

fn domainWarp(p: vec2<f32>, t: f32) -> vec2<f32> {
  let q = vec2<f32>(
    hash12(p + vec2<f32>(0.0, t * 0.1)),
    hash12(p + vec2<f32>(1.0, t * 0.1))
  );
  return p + (q - 0.5) * 0.3;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let aspect = resolution.x / resolution.y;

  let cellDensity = 4.0 + u.zoom_params.x * 20.0;
  let blastRadius = 0.3 + u.zoom_params.y * 0.5;
  let edgeGlowAmt = u.zoom_params.z;
  let chromaAmt = u.zoom_params.w;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;

  let mouse = u.zoom_config.yz;
  let mouseDist = length((uv - mouse) * vec2<f32>(aspect, 1.0));
  let centerDist = length(uv - vec2<f32>(0.5));
  var dist = select(centerDist, mouseDist, mouse.x >= 0.0);

  let rippleCount = u32(u.config.y);
  var blastEnergy = 0.0;
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let rd = length((uv - r.xy) * vec2<f32>(aspect, 1.0));
    let re = time - r.z;
    blastEnergy = blastEnergy + smoothstep(0.4, 0.0, rd) * exp(-re * 1.5);
  }

  let bassWave = sin(dist * 20.0 - time * 5.0) * 0.5 + 0.5;
  blastEnergy = blastEnergy + bassWave * bass * 0.3;

  let warpedUV = domainWarp(uv * cellDensity, time);
  let v = voronoi(warpedUV + blastEnergy * 2.0, time * 0.5);

  let cellCenter = floor(warpedUV) + 0.5;
  let cellUV = (cellCenter + 0.5) / cellDensity;
  let color = textureSampleLevel(readTexture, u_sampler, cellUV, 0.0);

  let edgeDist = v.y - v.x;
  let edgeMask = smoothstep(0.05, 0.0, edgeDist);
  let glowCol = vec3<f32>(0.2 + mids * 0.8, 0.5 + bass * 0.5, 1.0) * edgeMask * edgeGlowAmt * (1.0 + blastEnergy);

  let ca = chromaAmt * 0.02 * (1.0 + blastEnergy);
  let r = textureSampleLevel(readTexture, u_sampler, cellUV + vec2<f32>(ca, 0.0), 0.0).r;
  let b = textureSampleLevel(readTexture, u_sampler, cellUV - vec2<f32>(ca, 0.0), 0.0).b;
  let chromaCol = vec3<f32>(r, color.g, b);

  let internalGrad = 1.0 - v.x * 2.0;
  let shaded = chromaCol * (0.6 + internalGrad * 0.4) + glowCol;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthFade = mix(0.7, 1.0, depth);
  let blastFade = smoothstep(blastRadius, 0.0, dist);

  let centrality = 1.0 - v.x * 3.0;
  let alpha = clamp((blastEnergy * 0.5 + blastFade * 0.3) * centrality * depthFade + color.a * 0.3, 0.0, 1.0);

  let vig = 1.0 - 0.15 * smoothstep(0.3, 0.8, length(uv - 0.5));

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(shaded * vig, alpha));
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(shaded, blastEnergy));
}
