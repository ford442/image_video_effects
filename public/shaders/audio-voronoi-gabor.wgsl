// ═══════════════════════════════════════════════════════════════════
//  audio-voronoi-gabor
//  Category: advanced-hybrid
//  Features: audio-reactive, voronoi, gabor-texture, displacement-mapping,
//            mouse-driven, depth-aware
//  Complexity: Very High
//  Chunks From: audio-voronoi-displacement (audio Voronoi cells,
//               displacement), conv-gabor-texture-analyzer (oriented
//               texture detection, 4-orientation filter bank)
//  Created: 2026-04-18
//  By: Agent CB-7 — Flow & Multi-Pass Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Audio-reactive Voronoi displacement modulated by Gabor texture
//  analysis. Gabor responses detect local texture orientation and
//  strength, which rotate and scale Voronoi cell displacement.
//  Edges and textured regions displace differently than smooth areas.
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

// ═══ CHUNK: hash12 (from gen_grid.wgsl) ═══
fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// ═══ CHUNK: hash22 (from gen_grid.wgsl) ═══
fn hash22(p: vec2<f32>) -> vec2<f32> {
  var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.xx + p3.yz) * p3.zy);
}

// ═══ CHUNK: gaborResponse (from conv-gabor-texture-analyzer) ═══
fn gaborResponse(uv: vec2<f32>, theta: f32, freq: f32, sigma: f32, pixelSize: vec2<f32>) -> f32 {
  var response = 0.0;
  let radius = i32(ceil(sigma * 3.0));
  let maxRadius = min(radius, 4);
  let cosTheta = cos(theta);
  let sinTheta = sin(theta);
  for (var dy = -maxRadius; dy <= maxRadius; dy++) {
    for (var dx = -maxRadius; dx <= maxRadius; dx++) {
      let x = f32(dx);
      let y = f32(dy);
      let xTheta = x * cosTheta + y * sinTheta;
      let yTheta = -x * sinTheta + y * cosTheta;
      let gaussian = exp(-(xTheta*xTheta + yTheta*yTheta) / (2.0 * sigma * sigma + 0.001));
      let sinusoidal = cos(2.0 * 3.14159265 * freq * xTheta);
      let kernel = gaussian * sinusoidal;
      let offset = vec2<f32>(f32(dx), f32(dy)) * pixelSize;
      let luma = dot(textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
      response += luma * kernel;
    }
  }
  return response;
}

// ═══ AUDIO SIMULATION ═══
fn getAudioBands(uv: vec2<f32>, time: f32) -> vec3<f32> {
  var bass = 0.0;
  var mid = 0.0;
  var treble = 0.0;
  let bufSize = 256;
  let idx = i32(uv.x * 10.0) % bufSize;
  if (u32(idx) < arrayLength(&extraBuffer) / 4) {
    bass = extraBuffer[idx * 4] * 2.0;
    mid = extraBuffer[idx * 4 + 1] * 2.0;
    treble = extraBuffer[idx * 4 + 2] * 2.0;
  }
  if (bass < 0.01) {
    let beat = sin(time * 8.0) * 0.5 + 0.5;
    bass = pow(beat, 2.0) * 0.5 + 0.1;
    mid = sin(time * 12.0 + uv.x * 10.0) * 0.5 + 0.5;
    treble = sin(time * 20.0 + uv.y * 15.0) * 0.5 + 0.5;
  }
  return vec3<f32>(clamp(bass, 0.0, 1.0), clamp(mid, 0.0, 1.0), clamp(treble, 0.0, 1.0));
}

// ═══ VORONOI WITH AUDIO & GABOR ═══
fn voronoiAudioGabor(p: vec2<f32>, cellCount: f32, audioBands: vec3<f32>, gaborOrient: f32, gaborStrength: f32, time: f32) -> vec4<f32> {
  let cellSize = cellCount;
  let i = floor(p * cellSize);
  let f = fract(p * cellSize);
  var minDist1 = 1000.0;
  var minDist2 = 1000.0;
  var cellId = vec2<f32>(0.0);
  var cellCenter = vec2<f32>(0.0);
  for (var y: i32 = -1; y <= 1; y = y + 1) {
    for (var x: i32 = -1; x <= 1; x = x + 1) {
      let neighbor = vec2<f32>(f32(x), f32(y));
      let cell = i + neighbor;
      var hashVal = hash22(cell);
      let bassMod = audioBands.x * 0.3;
      let midMod = audioBands.y * 0.2;
      hashVal += vec2<f32>(
        sin(time * (1.0 + hashVal.x) + cell.x * 0.5) * bassMod,
        cos(time * (1.0 + hashVal.y) + cell.y * 0.5) * midMod
      );
      // Gabor influence: rotate cell centers by texture orientation
      let gaborRot = vec2<f32>(cos(gaborOrient), sin(gaborOrient)) * gaborStrength * 0.3;
      hashVal += gaborRot;
      let point = neighbor + hashVal;
      let dist = length(point - f);
      if (dist < minDist1) {
        minDist2 = minDist1;
        minDist1 = dist;
        cellId = cell;
        cellCenter = hashVal;
      } else if (dist < minDist2) {
        minDist2 = dist;
      }
    }
  }
  return vec4<f32>(minDist1, minDist2, cellId.x, cellCenter.x);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let id = vec2<i32>(global_id.xy);
  let pixelSize = 1.0 / resolution;

  // Parameters
  let cellCount = mix(5.0, 30.0, u.zoom_params.x);
  let audioReact = u.zoom_params.y * 2.0;
  let displacement = mix(0.0, 0.1, u.zoom_params.z);
  let gaborInfluence = u.zoom_params.w * 2.0;

  // Mouse interaction
  let mousePos = u.zoom_config.yz;
  let isMouseDown = u.zoom_config.w > 0.5;
  let distToMouse = length(uv - mousePos);
  let mouseGravity = 1.0 - smoothstep(0.0, 0.25, distToMouse);
  let clickPulse = select(0.0, 1.0, isMouseDown) * sin(distToMouse * 35.0 - time * 7.0) * exp(-distToMouse * 5.0);

  // ═══ GABOR TEXTURE ANALYSIS ═══
  let freq = 0.15;
  let sigma = 2.5;
  let r0 = gaborResponse(uv, 0.0, freq, sigma, pixelSize);
  let r45 = gaborResponse(uv, 0.785398, freq, sigma, pixelSize);
  let r90 = gaborResponse(uv, 1.570796, freq, sigma, pixelSize);
  let r135 = gaborResponse(uv, 2.356194, freq, sigma, pixelSize);

  // Dominant orientation and total texture strength
  let totalResponse = abs(r0) + abs(r45) + abs(r90) + abs(r135) + 0.001;
  let dominantAngle = atan2(r45 + r135 - r0 - r90, r0 + r45 - r90 - r135);
  let textureStrength = totalResponse * 0.5;

  // ═══ AUDIO BANDS ═══
  let audioBands = getAudioBands(uv, time);

  // ═══ VORONOI WITH TEXTURE-AWARE DISPLACEMENT ═══
  let voronoi = voronoiAudioGabor(uv, cellCount, audioBands * audioReact, dominantAngle, textureStrength * gaborInfluence, time);
  let dist1 = voronoi.x;
  let dist2 = voronoi.y;
  let cellHash = hash12(vec2<f32>(voronoi.z, voronoi.w));

  // Cell boundary
  let edge = smoothstep(0.05, 0.15, dist2 - dist1);

  // Texture-aware displacement: Gabor orientation rotates displacement
  let cellCenter = voronoi.w;
  let toCenter = vec2<f32>(cos(cellHash * 6.28 + dominantAngle * gaborInfluence), sin(cellHash * 6.28 + dominantAngle * gaborInfluence));
  let audioDisplacement = toCenter * audioBands.x * displacement * (1.0 + textureStrength * gaborInfluence);

  // Cursor displacement
  let cursorDisplacement = normalize(uv - mousePos + 0.001) * mouseGravity * 0.05 + clickPulse * 0.03;
  let displacedUV = clamp(uv + audioDisplacement + cursorDisplacement, vec2<f32>(0.0), vec2<f32>(1.0));

  // Sample image at displaced position
  var color = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).rgb;

  // Gabor-color mapping per cell
  let gaborColor = vec3<f32>(
    0.5 + 0.5 * cos(dominantAngle + 0.0),
    0.5 + 0.5 * cos(dominantAngle + 2.09),
    0.5 + 0.5 * cos(dominantAngle + 4.18)
  );

  // Color based on frequency bands per cell
  let freqColor = vec3<f32>(
    audioBands.x * cellHash * 1.5,
    audioBands.y * fract(cellHash * 1.618) * 1.5,
    audioBands.z * fract(cellHash * 2.618) * 1.5
  );

  // Blend: base + audio freq + Gabor texture color
  color = mix(color, color * (1.0 + freqColor), audioReact * 0.5);
  color = mix(color, color * gaborColor, textureStrength * gaborInfluence * 0.3);
  color *= (1.0 + mouseGravity * 0.5);

  // Cell edge glow
  let edgeGlow = (1.0 - edge) * audioBands.y * 0.5;
  color += vec3<f32>(edgeGlow * 0.8, edgeGlow * 0.6, edgeGlow);
  color += vec3<f32>(mouseGravity * 0.3, mouseGravity * 0.2, mouseGravity * 0.4);

  // Treble sparkle
  let sparkle = step(0.95, hash12(vec2<f32>(voronoi.z + time * 0.1))) * audioBands.z;
  color += vec3<f32>(sparkle);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let alpha = mix(0.7, 1.0, audioBands.x * audioReact + edgeGlow + textureStrength * 0.2);

  textureStore(writeTexture, id, vec4<f32>(clamp(color, vec3<f32>(0.0), vec3<f32>(2.0)), alpha));
  textureStore(writeDepthTexture, id, vec4<f32>(depth * (1.0 - audioBands.x * 0.1), 0.0, 0.0, 0.0));
}
