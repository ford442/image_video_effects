// ═══════════════════════════════════════════════════════════════════
//  Heat Haze
//  Category: distortion
//  Features: animated, atmospheric, mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-05-10
//  Upgraded: 2026-05-23
//  By: Phase A Upgrade Swarm
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
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  let coord = vec2<i32>(global_id.xy);
  var uv = vec2<f32>(global_id.xy) / resolution;
  let texel = 1.0 / resolution;

  // Params with randomization guards
  let heatGain = max(u.zoom_params.x, 0.001);
  let decayRate = max(u.zoom_params.y, 0.001);
  let diffusion = clamp(u.zoom_params.z, 0.0, 1.0);
  let refraction = max(u.zoom_params.w, 0.0);

  // Audio reactivity
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let audioBoost = 1.0 + bass * 0.5;

  // 1. Read previous heat (from Depth)
  // Diffusion: Sample neighbors
  let c = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let l = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(-texel.x, 0.0), 0.0).r;
  let r = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(texel.x, 0.0), 0.0).r;
  let t = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, -texel.y), 0.0).r;
  let b = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, texel.y), 0.0).r;

  let avg = (l + r + t + b) * 0.25;
  let diffusedHeat = mix(c, avg, diffusion);

  // 2. Add Mouse Heat (branchless)
  var mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let dist = distance(uv * vec2<f32>(aspect, 1.0), mousePos * vec2<f32>(aspect, 1.0));

  let inRadius = select(0.0, 1.0, dist < 0.05);
  let mouseHeat = select(0.0, heatGain * (1.0 - dist / 0.05), mouseDown > 0.5) * inRadius;

  let newHeat = (diffusedHeat + mouseHeat) * decayRate;

  // Clamp
  let finalHeat = clamp(newHeat, 0.0, 1.0);

  // Write Heat to Depth (for next frame)
  textureStore(writeDepthTexture, coord, vec4<f32>(finalHeat, 0.0, 0.0, 0.0));

  // 3. Render
  // Distort UV based on Heat Gradient (refraction)
  // We use the spatial gradient of the heat map
  let heatGradX = r - l;
  let heatGradY = b - t;
  let baseWarp = vec2<f32>(heatGradX, heatGradY) * refraction * audioBoost;

  // ═══ UNIQUE VISUAL IDEA: rising-convection columns + chromatic Schlieren ═══
  // Hot air does not just refract statically — it rises in shimmering columns.
  // We add an upward-scrolling, vertically-stretched turbulence so the haze
  // visibly convects, with mostly-horizontal wobble (columns sway side to side
  // as they ascend). Sampled at full-res frequency for fine shimmer.
  let convTime = u.config.x;
  let colUV = uv * vec2<f32>(38.0, 14.0) + vec2<f32>(0.0, -convTime * 1.6); // scrolls up
  let column = sin(colUV.x + sin(colUV.y) * 1.7) * cos(colUV.y * 0.8 + convTime);
  // Convection strength scales with local heat — only hot regions shimmer.
  let convStrength = finalHeat * refraction * audioBoost * 0.012;
  let convWarp = vec2<f32>(column * 1.4, abs(column) * 0.5) * convStrength;

  let warp = baseWarp + convWarp;

  // Chromatic Schlieren dispersion: hotter air bends short wavelengths more,
  // so blue refracts further than red — produces prismatic mirage fringing at
  // strong gradients. Spread scales with heat so cool areas stay aberration-free.
  let disp = (1.0 + finalHeat * 2.0);
  let uvR = uv - warp * (1.0 - 0.06 * disp);
  let uvG = uv - warp;
  let uvB = uv - warp * (1.0 + 0.06 * disp);
  let cr = textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r;
  let cg = textureSampleLevel(readTexture, u_sampler, uvG, 0.0);
  let cb = textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b;
  let color = vec4<f32>(cr, cg.g, cb, cg.a);

  // Add some thermal glow overlay
  let thermalTint = vec3<f32>(1.0, 0.3, 0.1) * finalHeat * 0.5 * audioBoost;

  // Meaningful alpha based on effect intensity and input luminance
  let lum = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));
  let outAlpha = clamp(color.a + finalHeat * 0.5 * audioBoost, 0.0, 1.0);

  let outColor = vec4<f32>(color.rgb + thermalTint, outAlpha);

  textureStore(writeTexture, coord, outColor);
  textureStore(dataTextureA, coord, outColor);
}
