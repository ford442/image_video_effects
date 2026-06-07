// ═══════════════════════════════════════════════════════════════════
//  Phase Memory Weave v3 — Optimized
//  Category: generative
//  Features: ginzburg-landau, allen-cahn, multi-scale-memory,
//            opalescent-interfaces, audio-driven, mouse-thermal
//  Upgrades: fast-atan2, branchless-audio, early-exit, named-consts,
//            TAU-constant, pm-alpha, reduced-sqrt-calls
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

const TAU: f32 = 6.28318530718;

// ── Fast atan2 (max error ~0.0015 rad, saves ~2 cycles vs builtin) ─
fn fast_atan2(y: f32, x: f32) -> f32 {
  let a = min(abs(x), abs(y)) / (max(abs(x), abs(y)) + 1e-6);
  let s = a * a;
  var r = ((-0.0464964749 * s + 0.15931422) * s - 0.327622764) * s * a + a;
  if (abs(y) > abs(x)) { r = 1.5707963 - r; }
  if (x < 0.0) { r = 3.1415927 - r; }
  if (y < 0.0) { r = -r; }
  return r;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = x * (2.51 * x + 0.03);
  let b = x * (2.43 * x + 0.59) + 0.14;
  return clamp(a / max(b, vec3<f32>(0.001)), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn thinFilmIridescence(phase: f32, d: f32) -> vec3<f32> {
  let phi = phase * TAU;
  return vec3<f32>(
    0.5 + 0.5 * cos(phi + d * 3.0),
    0.5 + 0.5 * cos(phi + d * 5.0 + 1.0),
    0.5 + 0.5 * cos(phi + d * 7.0 + 2.5)
  );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  let uv = vec2<f32>(gid.xy) / res;
  let time = u.config.x * 0.5;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;
  let clicks = u.config.y;
  let p1 = u.zoom_params.x;
  let p2 = u.zoom_params.y;
  let p3 = u.zoom_params.z;
  let p4 = u.zoom_params.w;

  let cur = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  let psiR = cur.r;
  let psiI = cur.g;
  let slowMem = cur.b;
  let rho2 = psiR * psiR + psiI * psiI;
  let rho = sqrt(rho2);
  let theta = fast_atan2(psiI, psiR);

  // Neighbor samples for laplacian + curvature
  let ps = 1.0 / res;
  let rx = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let lx = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let uy = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let dy = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

  let lapR = rx.r + lx.r + uy.r + dy.r - 4.0 * psiR;
  let lapI = rx.g + lx.g + uy.g + dy.g - 4.0 * psiI;

  // Ginzburg-Landau / Allen-Cahn dynamics
  let epsilon  = 0.035 + p3 * 0.04;
  let mobility = 0.15 + mids * 0.6 + p2 * 0.4;
  let reaction = rho * (1.0 - rho2);
  let dR = lapR * epsilon - reaction * psiR;
  let dI = lapI * epsilon - reaction * psiI;

  // Memory kernel (exponential-decay blend)
  let memoryBlend = mix(psiR, slowMem, 0.6);
  let memStrength = 0.2 + p2 * 0.7;
  let newR = mix(psiR + dR * mobility, memoryBlend, memStrength * 0.08);
  let newI = mix(psiI + dI * mobility, theta * 0.1, memStrength * 0.03);

  // Branchless audio seeding (replaces bass>0.55 per-pixel branch)
  let seedNoise = max(bass - 0.55, 0.0)
                * (fract(dot(uv, vec2<f32>(12.9898, 78.233)) + time * 0.2) - 0.5)
                * 0.4;

  // Capillary waves + mouse thermal injection (branchless select)
  let capillary = sin(uv.x * 30.0 + time * 4.0)
                * cos(uv.y * 24.0 - time * 3.5)
                * treble * 0.06;
  let mouseDist = length(uv - mouse);
  let thermal = smoothstep(0.15, 0.0, mouseDist) * mouseDown * (1.0 + p4 * 2.0);
  let isHeat = fract(clicks * 0.5) > 0.25;
  let thermalEffect = select(-thermal * 0.9, thermal * 0.6, isHeat);

  let finalR = clamp(newR + seedNoise + capillary + thermalEffect, -1.2, 1.2);
  let finalI = newI + capillary * 0.5;
  let finalRho = sqrt(finalR * finalR + finalI * finalI);
  let finalTheta = fast_atan2(finalI, finalR);

  // Curvature via neighbor magnitudes (4 sqrts kept for accuracy)
  let rhoRx = sqrt(rx.r * rx.r + rx.g * rx.g);
  let rhoLx = sqrt(lx.r * lx.r + lx.g * lx.g);
  let rhoUy = sqrt(uy.r * uy.r + uy.g * uy.g);
  let rhoDy = sqrt(dy.r * dy.r + dy.g * dy.g);
  let curvature = abs((rhoRx + rhoLx + rhoUy + rhoDy) - 4.0 * finalRho);

  // ── Early exit for quiescent background pixels ─────────────────
  if (finalRho < 0.03 && curvature < 0.02) {
    let newSlow = mix(slowMem, finalR, 0.12);
    textureStore(dataTextureA, gid.xy, vec4<f32>(finalR, finalI, newSlow, 0.0));
    textureStore(dataTextureB, gid.xy, vec4<f32>(newSlow, finalTheta, curvature, 0.0));
    textureStore(writeTexture, gid.xy, vec4<f32>(0.0, 0.0, 0.0, 0.0));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(0.0, 0.0, 0.0, 0.0));
    return;
  }

  // State writeback for slot chaining
  let newSlow = mix(slowMem, finalR, 0.12);
  textureStore(dataTextureA, gid.xy, vec4<f32>(finalR, finalI, newSlow, 0.0));
  textureStore(dataTextureB, gid.xy, vec4<f32>(newSlow, finalTheta, curvature, 0.0));

  // Opalescent thin-film interference + subsurface
  let irid = thinFilmIridescence(finalTheta, curvature * 5.0)
           * smoothstep(0.1, 0.4, curvature) * 0.8;
  let fluidMask  = smoothstep(0.5, 0.2, finalRho);
  let crystalMask = smoothstep(0.3, 0.7, finalRho);
  let caustic = pow(sin(finalTheta * 8.0 + time) * 0.5 + 0.5, 3.0) * fluidMask;
  let subsurface = crystalMask * vec3<f32>(0.85, 0.82, 0.75) * (0.6 + finalRho * 0.5);

  let fluidCol  = vec3<f32>(0.15, 0.35, 0.65) * (0.5 + caustic * 0.8);
  let crystalCol = vec3<f32>(0.92, 0.88, 0.72) * (0.5 + finalRho * 0.6);
  let baseCol = mix(fluidCol, crystalCol, crystalMask) + irid + subsurface;
  let tone = acesToneMap(baseCol * (0.7 + finalRho * 0.8) * (0.85 + p1 * 0.3));

  // Alpha encodes bloom weight (curvature = interface glow)
  let alpha = clamp(finalRho * 0.9 + curvature * 0.5, 0.0, 1.0);

  textureStore(writeTexture, gid.xy, vec4<f32>(tone * alpha, alpha));
  textureStore(writeDepthTexture, gid.xy, vec4<f32>(finalRho * 0.6 + crystalMask * 0.2, 0.0, 0.0, 0.0));
}
