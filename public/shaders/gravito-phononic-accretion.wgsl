// ═══════════════════════════════════════════════════════════════════
//  Gravito-Phononic Accretion v5 — High-End Optical Prism
//  Category: generative
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
  let a = x * (2.51 * x + 0.03);
  let b = x * (2.43 * x + 0.59) + 0.14;
  return clamp(a / max(b, vec3<f32>(0.001)), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn getAudioBins() -> vec3<f32> {
  // Read low, mid, and high frequency bins from plasmaBuffer
  let b1 = plasmaBuffer[1].x;
  let b2 = plasmaBuffer[5].x;
  let b3 = plasmaBuffer[9].x;
  return vec3<f32>(b1, b2, b3);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }
  
  let uv = vec2<f32>(gid.xy) / res;
  let coord = vec2<i32>(gid.xy);
  let time = u.config.x * 0.4;
  
  let bass = plasmaBuffer[0].x;
  let mid = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let bins = getAudioBins();
  
  // ── Persistent state strictly in extraBuffer[133..138] (single-writer) ──
  if (gid.x == 0u && gid.y == 0u) {
    let target = (bass + mid + treble) * 0.333;
    var springPos = extraBuffer[133];
    var springVel = extraBuffer[134];
    springVel += (target - springPos) * 0.15; // Spring force
    springVel *= 0.82;                        // Damping
    springPos += springVel;
    extraBuffer[133] = clamp(springPos, 0.0, 5.0);
    extraBuffer[134] = springVel;
  }
  let spring = extraBuffer[133];
  
  // ── Preserve exact parameters ──
  let p1 = u.zoom_params.x; // Accretion Speed   -> mass + flow gain
  let p2 = u.zoom_params.y; // Lensing Strength  -> real uv deflection
  let p3 = u.zoom_params.z; // Material Diffusion -> kernel + persistence
  let p4 = u.zoom_params.w; // Mouse Gravity Power
  
  let mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;
  
  // ── Continuous geometry: swirling optical centers ──
  let c1 = vec2<f32>(0.5 + 0.18 * cos(time * 0.6 + spring * 0.5), 0.5 + 0.18 * sin(time * 0.7));
  let c2 = vec2<f32>(0.5 + 0.15 * sin(time * 0.8), 0.5 + 0.15 * cos(time * 0.5 - spring * 0.4));
  
  var dir1 = c1 - uv;
  var dir2 = c2 - uv;
  let d1 = length(dir1);
  let d2 = length(dir2);
  
  // ── Velocity field (gravitational pull + orbital rotation) ──
  let pull1 = p1 * 0.005 / (d1 * d1 + 0.005);
  let pull2 = p1 * 0.005 / (d2 * d2 + 0.005);
  
  var flow = normalize(dir1) * pull1 + normalize(dir2) * pull2;
  flow += vec2<f32>(-dir1.y, dir1.x) * (bass * p2 * 0.015) / (d1 + 0.02);
  flow += vec2<f32>(-dir2.y, dir2.x) * (treble * p2 * 0.015) / (d2 + 0.02);
  
  // ── Held-pointer response ──
  let dMouse = length(uv - mouse);
  if (mouseDown > 0.0) {
      let mForce = p4 * 0.03 * (1.0 - smoothstep(0.0, 0.4, dMouse));
      flow += normalize(mouse - uv) * mForce / (dMouse + 0.01);
      // Optical swirl around pointer
      flow += vec2<f32>(-(mouse.y - uv.y), mouse.x - uv.x) * mForce * 1.5;
  }
  
  // ── Exact textureLoad from dataTextureC (no filtering) ──
  let flowOffset = vec2<i32>(flow * res);
  let advectCoord = coord - flowOffset;
  let clampedCoord = clamp(advectCoord, vec2<i32>(0), vec2<i32>(res - 1.0));
  var prev = textureLoad(dataTextureC, clampedCoord, 0).rgb;
  
  // ── Diffusion (cross-sampling via exact textureLoad) ──
  let t0 = textureLoad(dataTextureC, clamp(advectCoord + vec2<i32>(1, 0), vec2<i32>(0), vec2<i32>(res - 1.0)), 0).rgb;
  let t1 = textureLoad(dataTextureC, clamp(advectCoord + vec2<i32>(-1, 0), vec2<i32>(0), vec2<i32>(res - 1.0)), 0).rgb;
  let t2 = textureLoad(dataTextureC, clamp(advectCoord + vec2<i32>(0, 1), vec2<i32>(0), vec2<i32>(res - 1.0)), 0).rgb;
  let t3 = textureLoad(dataTextureC, clamp(advectCoord + vec2<i32>(0, -1), vec2<i32>(0), vec2<i32>(res - 1.0)), 0).rgb;
  
  let blurred = (prev * 2.0 + t0 + t1 + t2 + t3) / 6.0;
  prev = mix(prev, blurred, p3);
  
  // ── Prismatic palette injection ──
  let hue = fract(d1 * 2.5 - d2 * 2.0 - time * 0.3 + spring * 0.25);
  let cR = 0.5 + 0.5 * cos(6.28318 * (hue + 0.0));
  let cG = 0.5 + 0.5 * cos(6.28318 * (hue + 0.33));
  let cB = 0.5 + 0.5 * cos(6.28318 * (hue + 0.67));
  let prism = vec3<f32>(cR, cG, cB);
  
  let inject1 = smoothstep(0.05, 0.0, d1) * bass * 2.5;
  let inject2 = smoothstep(0.05, 0.0, d2) * treble * 2.5;
  let injectM = smoothstep(0.04, 0.0, dMouse) * mouseDown * p4 * 4.0;
  
  // ── Bounded spring + capped click fronts (ripples) ──
  var ripples = 0.0;
  let nR = min(u32(u.config.y), 50u);
  for (var i = 0u; i < nR; i++) {
      let rInfo = u.ripples[i];
      let d = length(uv - rInfo.xy);
      let t = (u.config.x - rInfo.z) * 1.5;
      if (t > 0.0 && t < 3.0) {
          let front = abs(d - t * 0.3);
          let capped = smoothstep(0.04, 0.0, front) * (1.0 - t/3.0);
          ripples += capped;
      }
  }
  
  // ── Combine & Decay ──
  let decay = mix(0.92, 0.995, p3);
  var color = prev * decay;
  
  color += prism * (inject1 + inject2 + injectM + ripples * 1.2) * 0.15;
  // Truthful three-band audio bins coloring
  color += vec3<f32>(bins.x, bins.y, bins.z) * 0.015;
  
  // ── ACES tone map on final color ──
  let finalColor = acesToneMap(color);
  
  // ── Semantic alpha ──
  let finalAlpha = clamp(length(finalColor) * 0.8, 0.0, 1.0);
  
  let outData = vec4<f32>(finalColor, finalAlpha);
  
  // ── Write final display RGBA ONLY to dataTextureA (and writeTexture) ──
  textureStore(dataTextureA, coord, outData);
  textureStore(writeTexture, coord, outData);
  textureStore(writeDepthTexture, coord, vec4<f32>(finalAlpha, 0.0, 0.0, 0.0));
}
