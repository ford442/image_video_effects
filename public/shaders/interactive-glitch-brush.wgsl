// ═══════════════════════════════════════════════════════════════════
//  Interactive Glitch Brush — Batch 58E
//  Sprung brush (extraBuffer[133..136], 0,0 writer), click grenades,
//  traveling scan-head conveyor, oil-slick phosphor on tears,
//  held-drag density, exact C paint persistence. Display RGBA in A.
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

fn random(st: vec2<f32>) -> f32 {
  return fract(sin(dot(st.xy, vec2<f32>(12.9898, 78.233))) * 43758.5453123);
}

fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
  let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  let p = abs(fract(hsv.xxx + k.xyz) * 6.0 - k.www);
  return hsv.z * mix(k.xxx, clamp(p - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), hsv.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }
  let coords = vec2<i32>(global_id.xy);
  let resolution = u.config.zw;
  var uv = vec2<f32>(global_id.xy) / max(resolution, vec2<f32>(1.0));
  let aspect = resolution.x / max(resolution.y, 1.0);
  let time = u.config.x;
  let mousePos = u.zoom_config.yz;
  let held = f32(u.zoom_config.w > 0.5);
  let prev = textureLoad(dataTextureC, coords, 0);

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let trebleBinR = plasmaBuffer[5].x;
  let trebleBinB = plasmaBuffer[8].x;

  let brushSize = max(u.zoom_params.x * 0.3 + 0.05, 0.001) * (1.0 + held * 0.22);
  let intensity = clamp(u.zoom_params.y, 0.0, 1.0);
  let blockScale = max(u.zoom_params.z * 50.0 + 5.0, 0.001);
  let colorSplit = clamp(u.zoom_params.w * 0.1, 0.0, 1.0);
  let audioIntensity = intensity * (1.0 + bass * 0.5 + mids * 0.25);

  let mouseValid = mousePos.x >= 0.0;
  let validF = select(0.0, 1.0, mouseValid);
  var sPos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  var sVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
  let snapF = step(length(sPos), 0.0001) * step(length(sVel), 0.0001) * validF;
  sPos = mix(sPos, mousePos, snapF);
  let springGoal = mix(sPos, mousePos, validF);
  let dt = 0.016;
  let stiffness = mix(60.0, 110.0, held);
  let damping = 2.0 * sqrt(stiffness);
  let force = (springGoal - sPos) * stiffness - sVel * damping;
  sVel = sVel + force * dt;
  sPos = sPos + sVel * dt;
  if (global_id.x == 0u && global_id.y == 0u) {
    extraBuffer[133] = sPos.x;
    extraBuffer[134] = sPos.y;
    extraBuffer[135] = sVel.x;
    extraBuffer[136] = sVel.y;
  }

  var color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let diffAspect = vec2<f32>((sPos.x - uv.x) * aspect, sPos.y - uv.y);
  let dist = length(diffAspect);
  let brushMask = validF * (1.0 - smoothstep(brushSize * 0.65, brushSize, dist));

  var grenade = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    let liveF = step(0.0, age) * step(age, 1.0);
    let rDist = length((rp.xy - uv) * vec2<f32>(aspect, 1.0));
    let zone = 1.0 - smoothstep(brushSize * 0.4, brushSize, rDist);
    grenade = max(grenade, zone * liveF * (1.0 - age));
  }

  let scanHead = pow(max(0.0, sin(uv.y * 48.0 - time * (14.0 + bass * 8.0))), 16.0);
  let conveyor = pow(max(0.0, sin(uv.x * aspect * 36.0 + time * (9.0 + mids * 6.0))), 10.0);
  let activeMask = clamp(max(brushMask, grenade) + scanHead * 0.18 * intensity, 0.0, 1.0);

  let blockUV = floor(uv * blockScale) / blockScale;
  let noise = random(blockUV + vec2<f32>(time * 0.1));
  let offsetX = select(0.0, (random(vec2<f32>(noise, time)) - 0.5) * audioIntensity * 0.2, noise > 0.5);
  let grenadeOffsetX = (random(blockUV + vec2<f32>(time * 0.37)) - 0.5) * 0.25;
  let dispX = select(offsetX, grenadeOffsetX, grenade > 0.05);
  let offset = vec2<f32>(dispX * activeMask + conveyor * 0.004 * activeMask, 0.0);

  let splitR = colorSplit * (0.5 + trebleBinR);
  let splitB = colorSplit * (0.5 + trebleBinB);
  let sampleUV_r = clamp(uv + offset - vec2<f32>(splitR, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
  let sampleUV_g = clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0));
  let sampleUV_b = clamp(uv + offset + vec2<f32>(splitB, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
  let r = textureSampleLevel(readTexture, u_sampler, sampleUV_r, 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, sampleUV_g, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, sampleUV_b, 0.0).b;

  let invertBase = step(0.95, random(vec2<f32>(time, noise)));
  let invertNade = step(0.25, grenade) * step(0.5, random(blockUV + vec2<f32>(time * 0.73)));
  let invertCond = max(invertBase, invertNade) > 0.5;
  let glitchR = select(r, 1.0 - r, invertCond);
  let glitchG = select(g, 1.0 - g, invertCond);
  let glitchB = select(b, 1.0 - b, invertCond);
  let glitchLuma = 0.299 * glitchR + 0.587 * glitchG + 0.114 * glitchB;
  var glitchColor = vec4<f32>(glitchR, glitchG, glitchB, clamp(glitchLuma + treble * 0.1, 0.1, 1.0));
  glitchColor = vec4<f32>(glitchColor.rgb * (1.0 + grenade * 0.35), glitchColor.a);
  let scanlineCond = fract(uv.y * resolution.y * 0.5) < 0.5;
  glitchColor = select(glitchColor, glitchColor * 0.8, scanlineCond);

  let slick = hsv2rgb(vec3<f32>(fract(0.78 + noise * 0.2 + mids * 0.15 + time * 0.11), 0.75, 1.0));
  glitchColor = vec4<f32>(mix(glitchColor.rgb, glitchColor.rgb * slick * 1.2, 0.2 + treble * 0.2), glitchColor.a);
  glitchColor = vec4<f32>(glitchColor.rgb + slick * (scanHead * 0.18 + conveyor * 0.12 + grenade * 0.25), glitchColor.a);

  color = mix(color, glitchColor, activeMask);
  color = mix(color, prev, 0.22 * (1.0 - activeMask * 0.4));

  let depth = textureLoad(readDepthTexture, coords, 0).r;
  textureStore(writeTexture, coords, color);
  textureStore(dataTextureA, coords, color);
  textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
