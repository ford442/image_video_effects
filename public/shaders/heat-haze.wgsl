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
  let time = u.config.x;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let maxCoord = vec2<i32>(resolution) - vec2<i32>(1);

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

  // Advect packed heat upward, then diffuse using exact bounded state loads.
  let risePixels = 1 + i32(round((1.0 - decayRate) * 2.0 + bass * 2.0));
  let sourceCoord = clamp(coord + vec2<i32>(0, risePixels), vec2<i32>(0), maxCoord);
  let c = textureLoad(readDepthTexture, sourceCoord, 0).r;
  let l = textureLoad(readDepthTexture, clamp(sourceCoord + vec2<i32>(-1, 0), vec2<i32>(0), maxCoord), 0).r;
  let r = textureLoad(readDepthTexture, clamp(sourceCoord + vec2<i32>(1, 0), vec2<i32>(0), maxCoord), 0).r;
  let t = textureLoad(readDepthTexture, clamp(sourceCoord + vec2<i32>(0, -1), vec2<i32>(0), maxCoord), 0).r;
  let b = textureLoad(readDepthTexture, clamp(sourceCoord + vec2<i32>(0, 1), vec2<i32>(0), maxCoord), 0).r;

  let avg = (l + r + t + b) * 0.25;
  let diffusedHeat = mix(c, avg, diffusion);

  // 2. Add Mouse Heat (branchless)
  var mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;
  let dist = distance(uv * vec2<f32>(aspect, 1.0), mousePos * vec2<f32>(aspect, 1.0));

  let inRadius = select(0.0, 1.0, dist < 0.05);
  let mouseHeat = select(0.0, heatGain * (1.0 - dist / 0.05), mouseDown > 0.5) * inRadius;

  var clickHeat = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 1.8) {
      let delta = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
      clickHeat += smoothstep(0.026, 0.0, abs(length(delta) - age * 0.38)) * exp(-age * 1.45);
    }
  }

  let retention = 1.0 - mix(0.008, 0.12, decayRate);
  let newHeat = diffusedHeat * retention + mouseHeat + clickHeat * heatGain * 0.35;

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
  let convTime = time;
  let colUV = uv * vec2<f32>(38.0, 14.0) + vec2<f32>(0.0, -convTime * 1.6); // scrolls up
  let column = sin(colUV.x + sin(colUV.y) * 1.7) * cos(colUV.y * 0.8 + convTime);
  // Convection strength scales with local heat — only hot regions shimmer.
  let convStrength = finalHeat * refraction * audioBoost * 0.012;
  let convWarp = vec2<f32>(column * 1.4, abs(column) * 0.5) * convStrength;

  // Narrow heat packets race upward through the broader convection columns.
  let heatRunner = pow(max(0.0, sin(uv.y * 86.0 + uv.x * 19.0 - time * 17.0)), 14.0) * finalHeat;
  let runnerWarp = vec2<f32>(sin(uv.y * 35.0 + time * 9.0), -1.0) * heatRunner * refraction * 0.012;

  let warp = baseWarp + convWarp + runnerWarp;

  // Chromatic Schlieren dispersion: hotter air bends short wavelengths more,
  // so blue refracts further than red — produces prismatic mirage fringing at
  // strong gradients. Spread scales with heat so cool areas stay aberration-free.
  let disp = (1.0 + finalHeat * 2.0);
  let uvR = clamp(uv - warp * (1.0 - 0.06 * disp), vec2<f32>(0.0), vec2<f32>(1.0));
  let uvG = clamp(uv - warp, vec2<f32>(0.0), vec2<f32>(1.0));
  let uvB = clamp(uv - warp * (1.0 + 0.06 * disp), vec2<f32>(0.0), vec2<f32>(1.0));
  let cr = textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r;
  let cg = textureSampleLevel(readTexture, u_sampler, uvG, 0.0);
  let cb = textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b;
  let color = vec4<f32>(cr, cg.g, cb, cg.a);

  // Add some thermal glow overlay
  let thermalTint = vec3<f32>(1.0, 0.3, 0.1) * (finalHeat * 0.5 + heatRunner * 0.18) * audioBoost;

  // Meaningful alpha based on effect intensity and input luminance
  let lum = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));
  let outAlpha = clamp(color.a + finalHeat * 0.5 * audioBoost, 0.0, 1.0);

  let outColor = vec4<f32>(clamp(color.rgb + thermalTint, vec3<f32>(0.0), vec3<f32>(4.0)), outAlpha);

  textureStore(writeTexture, coord, outColor);
  textureStore(dataTextureA, coord, outColor);
}
