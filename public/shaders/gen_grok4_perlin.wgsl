// ═══════════════════════════════════════════════════════════════════
//  Stratified Erosion Terrain
//  Category: generative
//  Features: upgraded-rgba, depth-aware, audio-reactive, procedural, mouse-driven, temporal
//  Complexity: Very High
//  Scientific: Sediment-transport terrain with hydraulic incision, wind abrasion, layered hardness, seismic uplift, and reflective water-table basins
//  Upgraded: 2026-05-23
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn clampCoord(p: vec2<i32>, size: vec2<i32>) -> vec2<i32> {
  return clamp(p, vec2<i32>(0, 0), size - vec2<i32>(1, 1));
}

fn saturate(x: f32) -> f32 {
  return clamp(x, 0.0, 1.0);
}

fn hash12(p: vec2<f32>) -> f32 {
  let h = vec2<f32>(
    dot(p, vec2<f32>(127.1, 311.7)),
    dot(p, vec2<f32>(269.5, 183.3))
  );
  return fract(sin(dot(h, vec2<f32>(1.0, 1.3))) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u2 = f * f * (3.0 - 2.0 * f);
  let a = hash12(i);
  let b = hash12(i + vec2<f32>(1.0, 0.0));
  let c = hash12(i + vec2<f32>(0.0, 1.0));
  let d = hash12(i + vec2<f32>(1.0, 1.0));
  return mix(mix(a, b, u2.x), mix(c, d, u2.x), u2.y);
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var value = 0.0;
  var amplitude = 0.5;
  var frequency = 1.0;
  for (var i: i32 = 0; i < 6; i = i + 1) {
    if (i >= octaves) {
      break;
    }
    value += amplitude * valueNoise(p * frequency);
    amplitude *= 0.5;
    frequency *= 2.05;
  }
  return value;
}

fn ridgedFbm(p: vec2<f32>) -> f32 {
  var value = 0.0;
  var amplitude = 0.65;
  var frequency = 1.0;
  for (var i: i32 = 0; i < 5; i = i + 1) {
    let n = valueNoise(p * frequency) * 2.0 - 1.0;
    value += (1.0 - abs(n)) * amplitude;
    amplitude *= 0.55;
    frequency *= 2.12;
  }
  return value;
}

fn terrainBase(uv: vec2<f32>, time: f32, mouse: vec2<f32>, terrainScale: f32) -> f32 {
  let scale = mix(1.8, 8.4, terrainScale);
  let mouseOffset = (mouse - 0.5) * vec2<f32>(1.9, -1.5);
  var p = uv * scale + mouseOffset * 0.65;

  let warp = vec2<f32>(
    fbm(p * 0.55 + vec2<f32>(time * 0.05, -time * 0.04), 4),
    fbm(p * 0.55 + vec2<f32>(4.8 - time * 0.03, 1.2 + time * 0.05), 4)
  );
  p += (warp - 0.5) * 1.6;

  let continental = fbm(p * 0.6 + vec2<f32>(-time * 0.02, time * 0.01), 5);
  let ridges = ridgedFbm(p * 1.35 + 3.1);
  let valleys = fbm(p * 2.3 - 11.7, 4);
  var h = continental * 0.58 + ridges * 0.42;
  h -= valleys * 0.12;
  return clamp(h, 0.0, 1.0);
}

fn sampleState(uv: vec2<f32>, resolution: vec2<f32>, size: vec2<i32>) -> vec4<f32> {
  let pos = clamp(uv * resolution - vec2<f32>(0.5), vec2<f32>(0.0), resolution - vec2<f32>(1.001));
  let i0 = vec2<i32>(i32(floor(pos.x)), i32(floor(pos.y)));
  let f = fract(pos);
  let c00 = textureLoad(dataTextureC, clampCoord(i0, size), 0);
  let c10 = textureLoad(dataTextureC, clampCoord(i0 + vec2<i32>(1, 0), size), 0);
  let c01 = textureLoad(dataTextureC, clampCoord(i0 + vec2<i32>(0, 1), size), 0);
  let c11 = textureLoad(dataTextureC, clampCoord(i0 + vec2<i32>(1, 1), size), 0);
  return mix(mix(c00, c10, f.x), mix(c01, c11, f.x), f.y);
}

fn layerHardness(height: f32, uv: vec2<f32>, time: f32) -> f32 {
  let layers = 0.5 + 0.5 * sin(height * 120.0 + fbm(uv * 18.0 + time * 0.05, 3) * 8.0);
  let crystalline = ridgedFbm(uv * 9.5 + vec2<f32>(3.0, -2.0));
  return clamp(0.22 + 0.68 * (layers * 0.72 + crystalline * 0.28), 0.18, 0.95);
}

fn faultMask(uv: vec2<f32>, time: f32) -> f32 {
  let folded = abs(sin((uv.x * 12.0 + fbm(uv * 9.0 + time * 0.04, 3) * 4.0) * 3.14159));
  return smoothstep(0.72, 0.98, 1.0 - folded);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }

  let coord = vec2<i32>(global_id.xy);
  let size = vec2<i32>(i32(resolution.x), i32(resolution.y));
  let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
  let px = 1.0 / resolution;
  let time = u.config.x * 0.12;

  let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let erosionControl = saturate(u.zoom_params.x);
  let waterTable = mix(0.18, 0.62, u.zoom_params.y);
  let terrainScale = saturate(u.zoom_params.z);
  let windControl = saturate(u.zoom_params.w);
  let mouse = u.zoom_config.yz;
  let mouseMask = (1.0 - smoothstep(0.0, 0.12, distance(uv, mouse))) * u.zoom_config.w;

  let prev = textureLoad(dataTextureC, coord, 0);
  let base = terrainBase(uv, time, mouse, terrainScale);

  let leftState = textureLoad(dataTextureC, clampCoord(coord + vec2<i32>(-1, 0), size), 0);
  let rightState = textureLoad(dataTextureC, clampCoord(coord + vec2<i32>(1, 0), size), 0);
  let downState = textureLoad(dataTextureC, clampCoord(coord + vec2<i32>(0, -1), size), 0);
  let upState = textureLoad(dataTextureC, clampCoord(coord + vec2<i32>(0, 1), size), 0);

  let h = clamp(base + prev.a - prev.r, 0.0, 1.0);
  let hL = clamp(terrainBase(uv + vec2<f32>(-px.x, 0.0), time, mouse, terrainScale) + leftState.a - leftState.r, 0.0, 1.0);
  let hR = clamp(terrainBase(uv + vec2<f32>( px.x, 0.0), time, mouse, terrainScale) + rightState.a - rightState.r, 0.0, 1.0);
  let hD = clamp(terrainBase(uv + vec2<f32>(0.0, -px.y), time, mouse, terrainScale) + downState.a - downState.r, 0.0, 1.0);
  let hU = clamp(terrainBase(uv + vec2<f32>(0.0,  px.y), time, mouse, terrainScale) + upState.a - upState.r, 0.0, 1.0);

  let gradient = vec2<f32>(hR - hL, hU - hD) * 0.5;
  let slope = length(gradient);
  let hardness = layerHardness(base, uv, time);
  let gust = (0.015 + treble * 0.035 + windControl * 0.05) * (0.55 + 0.45 * fbm(uv * 15.0 + vec2<f32>(time * 0.3, 0.0), 3));
  let flowVelocity = vec2<f32>(-gradient.x * (0.35 + prev.b * 0.9) + gust, -gradient.y * (0.25 + prev.b * 0.55));
  let advected = sampleState(uv - flowVelocity * 0.08, resolution, size);

  let basin = (1.0 - smoothstep(0.03, 0.18, slope)) * (1.0 - smoothstep(waterTable + 0.02, waterTable + 0.25, h));
  let pondDepth = max(waterTable - h, 0.0);
  let newWater = saturate(advected.b * 0.992 + pondDepth * 1.35 + basin * 0.04 - slope * 0.025);

  let velocity2 = dot(flowVelocity, flowVelocity) * 220.0;
  let windAbrasion = abs(hR - hL) * gust * (0.35 + (1.0 - hardness)) * (0.25 + windControl * 1.4);
  let erosionRate = erosionControl * velocity2 * (0.18 + newWater * 1.35) * (1.0 - hardness);
  let depositionRate = advected.g * advected.g * (0.2 + basin * 1.5) * (0.25 + hardness * 0.45);

  let seismicPulse = smoothstep(0.78, 0.98, bass) * faultMask(uv, time) * (0.008 + 0.024 * hash12(floor(uv * 28.0) + floor(time * 6.0)));
  let mouseUplift = mouseMask * 0.045;

  let newUplift = clamp(advected.a * 0.992 + seismicPulse + mouseUplift, 0.0, 0.35);
  let newSediment = saturate(advected.g + erosionRate * 0.7 + windAbrasion * 0.4 - depositionRate * 0.65);
  let newErosion = clamp(advected.r * 0.996 + erosionRate * 0.18 + windAbrasion * 0.12 - depositionRate * 0.08 - seismicPulse * 0.45 - mouseUplift * 0.35, 0.0, 0.72);

  let height = clamp(base + newUplift - newErosion, 0.0, 1.0);
  let waterMask = saturate(pondDepth * 5.0 + basin * 0.35 + newWater * 0.45);

  let normal = normalize(vec3<f32>(-(hR - hL) * 10.0, 1.0, -(hU - hD) * 10.0));
  let lightDir = normalize(vec3<f32>(0.58, 0.75, -0.32));
  let diffuse = clamp(dot(normal, lightDir), 0.0, 1.0);
  let ambient = 0.3;
  let viewDir = normalize(vec3<f32>(0.0, 1.0, 0.6));
  let halfDir = normalize(lightDir + viewDir);
  let specular = pow(max(dot(normal, halfDir), 0.0), 28.0);
  let strata = 0.5 + 0.5 * sin((height - newErosion * 0.35 + newSediment * 0.15) * 95.0 + fbm(uv * 18.0, 3) * 6.0);

  var landColor = vec3<f32>(0.16, 0.14, 0.12);
  landColor = mix(landColor, vec3<f32>(0.52, 0.44, 0.30), smoothstep(waterTable - 0.02, waterTable + 0.08, height));
  landColor = mix(landColor, vec3<f32>(0.20, 0.36, 0.22), smoothstep(waterTable + 0.04, waterTable + 0.24, height));
  landColor = mix(landColor, vec3<f32>(0.43, 0.38, 0.32), smoothstep(0.55, 0.8, height));
  landColor = mix(landColor, vec3<f32>(0.92, 0.94, 0.98), smoothstep(0.82, 0.98, height));
  landColor += vec3<f32>(0.10, 0.08, 0.05) * (strata - 0.5) * 0.55;
  landColor += vec3<f32>(0.20, 0.14, 0.09) * windAbrasion * 1.8;
  landColor += vec3<f32>(0.12, 0.09, 0.05) * newSediment * (0.5 + mids * 0.8);

  let skyReflection = mix(vec3<f32>(0.08, 0.16, 0.28), vec3<f32>(0.65, 0.78, 0.92), 1.0 - uv.y);
  let waterColor = mix(vec3<f32>(0.04, 0.11, 0.20), skyReflection, smoothstep(0.0, 0.35, waterMask));
  let reflective = smoothstep(0.1, 0.55, waterMask) * (0.2 + specular * 0.9);

  var generatedColor = mix(landColor, waterColor, waterMask);
  generatedColor *= ambient + diffuse * 0.95;
  generatedColor += vec3<f32>(1.0) * reflective;
  generatedColor += vec3<f32>(0.08, 0.10, 0.12) * pow(1.0 - clamp(normal.y, 0.0, 1.0), 2.0) * 0.35;

  let valleyFog = smoothstep(0.0, 0.4, 1.0 - height + waterMask * 0.25);
  let fogColor = mix(vec3<f32>(0.62, 0.72, 0.82), vec3<f32>(0.92, 0.95, 0.98), uv.y);
  generatedColor = mix(generatedColor, fogColor, valleyFog * 0.42);

  let finalColor = mix(inputColor.rgb, generatedColor, 0.94);
  let finalAlpha = max(inputColor.a, 0.88 + waterMask * 0.08);
  let finalDepth = mix(inputDepth, height, 0.96);

  textureStore(writeTexture, coord, vec4<f32>(finalColor, finalAlpha));
  textureStore(dataTextureA, coord, vec4<f32>(newErosion, newSediment, newWater, newUplift));
  textureStore(dataTextureB, coord, vec4<f32>(height, slope, waterMask, hardness));
  textureStore(writeDepthTexture, coord, vec4<f32>(finalDepth, 0.0, 0.0, 0.0));
}
