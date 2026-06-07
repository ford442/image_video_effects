// ═══════════════════════════════════════════════════════════════════
//  Ripple Blocks
//  Category: visual-effects
//  Features: ripple, blocks, retro, audio-wave, depth-stack, light-bleed, tactile-ripple
//  Complexity: Medium
//  Updated: 2026-05-31
//  By: Grok (visual flourish — richer wave propagation, audio stacking, atmospheric light bleed)
// ═══════════════════════════════════════════════════════════════════
//  Upgraded: 2026-05-31 (Algorithmist + Visualist + Interactivist + Optimizer)
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=GridScale, y=WarpAmount, z=GlowIntensity, w=TrailPersistence
  ripples: array<vec4<f32>, 50>,
};

// ─── Algorithmist: Noise foundation ───
fn hash2(p: vec2<f32>) -> vec2<f32> {
  var pp = fract(p * vec2(0.1031, 0.1030));
  pp += dot(pp, pp.yx + 33.33);
  return fract((pp.xy + pp.yx) * pp.yx);
}

fn vnoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash2(i).x, hash2(i + vec2(1.0, 0.0)).x, u.x),
             mix(hash2(i + vec2(0.0, 1.0)).x, hash2(i + vec2(1.0, 1.0)).x, u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var pp = p;
  for (var i = 0; i < 4; i++) {
    v += a * vnoise(pp);
    pp = pp * 2.1 + vec2(3.3, 1.7);
    a *= 0.5;
  }
  return v;
}

fn domainWarp(uv: vec2<f32>, t: f32) -> vec2<f32> {
  let q = vec2(fbm(uv + vec2(0.0, t * 0.1)), fbm(uv + vec2(5.2, 1.3 + t * 0.1)));
  let r = vec2(fbm(uv + 3.0 * q + vec2(1.7, 9.2)), fbm(uv + 3.0 * q + vec2(8.3, 2.8)));
  return uv + 0.5 * r;
}

// ─── Visualist: Color science ───
fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3(0.0), vec3(1.0));
}

fn tempColor(t: f32) -> vec3<f32> {
  return mix(vec3(1.0, 0.35, 0.08), vec3(0.45, 0.75, 1.0), clamp(t, 0.0, 1.0));
}

// ─── Optimizer: Assembled kernel ───
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  if (gid.x >= u32(u.config.z) || gid.y >= u32(u.config.w)) { return; }
  let dims = vec2<f32>(u.config.zw);
  let uv = vec2<f32>(gid.xy) / dims;
  let coord = vec2<i32>(gid.xy);
  let t = u.config.x;

  // Interactivist: Multi-band audio + input cache
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

    // Grok visual flourish: Richer wave stacking and light interaction
    let waveDrive = 1.0 + bass * 0.5 + mids * 0.3;
  let env = 1.0 + bass * 2.0;
  let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  // Parameters
  let gridScale = 5.0 + u.zoom_params.x * 40.0;
  let warpAmt = u.zoom_params.y;
  let glowIntensity = u.zoom_params.z * 2.0;
  let trailPersistence = u.zoom_params.w;
  let aspect = dims.x / dims.y;
  let mouse = u.zoom_config.yz;

  // Algorithmist: Domain-warped grid
  var warpedUV = uv;
  if (warpAmt > 0.001) {
    warpedUV = domainWarp(uv * gridScale, t) / gridScale;
  }
  let gridUV = warpedUV * vec2(gridScale, gridScale / aspect);
  let cellId = floor(gridUV);
  let cellCenter = (cellId + 0.5) / vec2(gridScale, gridScale / aspect);

  // Interactivist: Mouse + ripple shockwaves
  let mouseVec = cellCenter - mouse;
  let mouseDist = length(vec2(mouseVec.x * aspect, mouseVec.y));
  var rippleDist = 0.0;
  let rc = u32(u.config.y);
  for (var i = 0u; i < rc; i = i + 1u) {
    let rp = u.ripples[i].xy;
    let rt = t - u.ripples[i].z;
    let rpd = length(cellCenter - rp);
    rippleDist += exp(-rpd * 3.0) * sin(rpd * 30.0 - rt * 8.0) * 0.5;
  }

  // Algorithmist: Cymatics interference (golden-ratio detuned waves + FBM)
  let waveTime = t * 2.0;
  let d = mouseDist + rippleDist;
  let freq = 20.0 + mids * 30.0;
  let w1 = sin(d * freq - waveTime);
  let w2 = sin(d * freq * 1.618 - waveTime * 1.3) * 0.5;
  let w3 = (fbm(uv * 8.0 + t * 0.1) * 2.0 - 1.0) * 0.3;
  let interference = w1 + w2 + w3;
  let falloff = 1.0 / (1.0 + mouseDist * 3.0);
  let scaleMod = interference * falloff * env;
  let scale = 1.0 - scaleMod * 0.6;

  // Cell UV scaling
  let uvCentered = uv - cellCenter;
  let uvScaled = uvCentered / max(0.01, scale) + cellCenter;
  let cellMin = cellId / vec2(gridScale, gridScale / aspect);
  let cellMax = (cellId + 1.0) / vec2(gridScale, gridScale / aspect);
  let inBounds = uvScaled.x >= cellMin.x && uvScaled.x <= cellMax.x && uvScaled.y >= cellMin.y && uvScaled.y <= cellMax.y;

  // Interactivist: Depth parallax + sample
  let parallax = (1.0 - depth) * 0.02 * scaleMod;
  let sampleUV = clamp(uvScaled + parallax, vec2(0.0), vec2(1.0));
  let cellColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);

  // Visualist: HDR lighting & color grading
  var col = select(vec3(0.0), cellColor.rgb, inBounds);
  let edgeDist = min(min(abs(uvScaled.x - cellMin.x), abs(uvScaled.x - cellMax.x)), min(abs(uvScaled.y - cellMin.y), abs(uvScaled.y - cellMax.y)));
  let rim = exp(-edgeDist * gridScale * 10.0);
  col += vec3(0.4, 0.8, 1.0) * rim * glowIntensity * env;
  col += tempColor(mids) * abs(scaleMod) * 0.5 * glowIntensity;
  let spark = hash2(cellId + t).x;
  col += vec3(1.0, 0.95, 0.8) * step(0.97 - treble * 0.1, spark) * treble * 2.0;

  // Interactivist: Temporal feedback trails
  let prevFrame = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  col = max(col, prevFrame.rgb * trailPersistence * 0.8);

  // Visualist: ACES tone map + hue preserve clamp
  col = aces(col * 1.2);
  var alpha = select(0.1, 0.85 + abs(scaleMod) * 0.15, inBounds);
  alpha *= (1.0 - depth * 0.3);
  let lum = dot(col, vec3(0.299, 0.587, 0.114));
  col = max(clamp(col, vec3(0.0), vec3(1.0)), lum * vec3(0.2, 0.25, 0.3));

  // Premultiplied composite
  let finalRGB = col * alpha + inputColor.rgb * (1.0 - alpha);
  textureStore(writeTexture, coord, vec4(finalRGB, alpha));
  textureStore(dataTextureA, coord, vec4(finalRGB, alpha));
  textureStore(writeDepthTexture, coord, vec4(depth * (1.0 - alpha * 0.5), 0.0, 0.0, 1.0));
}
