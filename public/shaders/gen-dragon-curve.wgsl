// ═══════════════════════════════════════════════════════════════════
//  Heighway Dragon Curve
//  Category: generative
//  Features: procedural, fractal, dragon-curve, l-system, neon-line,
//            audio-reactive, mouse-driven, aces-tonemap, chromatic-aberration,
//            temporal-feedback, depth-aware, upgraded-rgba
//  Complexity: High
//  Created: 2026-05-30
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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn segDist(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
  let ab = b - a;
  let ap = p - a;
  let t = clamp(dot(ap, ab) / (dot(ab, ab) + 1e-8), 0.0, 1.0);
  return length(ap - ab * t);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if gid.x >= dims.x || gid.y >= dims.y { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(dims);
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mouse = u.zoom_config.yz;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let zoom = mix(0.8, 4.0, u.zoom_params.x);
  let glowWidth = mix(0.015, 0.004, u.zoom_params.y);
  let caAmt = u.zoom_params.z * 0.08;
  let feedback = u.zoom_params.w;

  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  let mp = (mouse - 0.5) * vec2<f32>(aspect, 1.0) * 0.3;
  var p = ((uv - 0.5) * vec2<f32>(aspect, 1.0) - mp) * zoom * 40.0 + vec2<f32>(16.0, 8.0);

  // Bass drives iteration depth
  let maxSeg = u32(mix(256.0, 512.0, clamp(bass * 1.2, 0.0, 1.0)));
  let segLen = mix(0.08, 0.04, depth);

  var pos = vec2<f32>(0.0, 0.0);
  var dir = vec2<f32>(segLen, 0.0);
  var minDist = 1e9;
  var closestIdx = 0u;
  var closestTurn = false;

  for (var i = 0u; i < maxSeg; i = i + 1u) {
    let a = pos;
    pos = pos + dir;
    let b = pos;

    let d = segDist(p, a, b);
    if d < minDist {
      minDist = d;
      closestIdx = i;
      let n = i + 1u;
      let lsb = n & (0u - n);
      closestTurn = ((lsb << 1u) & n) != 0u;
    }

    // Turn for next segment
    let n = i + 1u;
    let lsb = n & (0u - n);
    let turn = ((lsb << 1u) & n) != 0u;
    dir = select(vec2<f32>(dir.y, -dir.x), vec2<f32>(-dir.y, dir.x), turn);
  }

  // Turn intensity: detect fold changes
  let n1 = closestIdx + 1u;
  let lsb1 = n1 & (0u - n1);
  let t1 = ((lsb1 << 1u) & n1) != 0u;
  let n2 = closestIdx + 2u;
  let lsb2 = n2 & (0u - n2);
  let t2 = ((lsb2 << 1u) & n2) != 0u;
  let turnIntensity = 1.0 + select(0.0, 0.6, t1 != t2);

  // Neon hue by iteration depth
  let hue = mix(0.0, 0.88, f32(closestIdx) / f32(maxSeg));
  let sat = 0.85 + bass * 0.15;
  let h = fract(hue) * 6.0;
  let c = sat;
  let x = c * (1.0 - abs(fract(h * 0.5) * 2.0 - 1.0));
  let m = 1.0 - c;
  var neon: vec3<f32>;
  if h < 1.0 { neon = vec3<f32>(c, x, 0.0); }
  else if h < 2.0 { neon = vec3<f32>(x, c, 0.0); }
  else if h < 3.0 { neon = vec3<f32>(0.0, c, x); }
  else if h < 4.0 { neon = vec3<f32>(0.0, x, c); }
  else if h < 5.0 { neon = vec3<f32>(x, 0.0, c); }
  else { neon = vec3<f32>(c, 0.0, x); }
  neon = neon + vec3<f32>(m);

  // HDR glow
  let glow = exp(-minDist / glowWidth) * turnIntensity;
  var color = neon * glow * 2.5;

  // Chromatic aberration on tight folds
  let fold = select(0.0, 1.0, t1 != t2) * smoothstep(0.0, glowWidth * 3.0, glow);
  color = vec3<f32>(color.r * (1.0 + fold * caAmt), color.g,
                    color.b * (1.0 - fold * caAmt * 0.5));

  color = acesToneMap(color);

  // Temporal persistence
  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
  color = mix(color, prev * 0.95, 0.04 + feedback * 0.06 + bass * 0.02);

  // Depth controls line thickness perspective
  let curveDensity = exp(-minDist / (glowWidth * (1.0 + depth)));
  let alpha = curveDensity * turnIntensity * (0.3 + depth * 0.7);

  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(curveDensity * depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, vec4<f32>(color, alpha));
}
