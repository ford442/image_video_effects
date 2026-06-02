// ================================================================
//  Hex Lens Interactive
//  Category: image
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba, chromatic-aberration
//  Complexity: Medium
//  Chunks From: hex-lens
//  Created: 2026-05-30
//  By: Copilot
// ================================================================

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
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=TileSize, y=LensZoom, z=Rotation, w=MouseInfluence
  ripples: array<vec4<f32>, 50>,
};

fn rotate(v: vec2<f32>, angle: f32) -> vec2<f32> {
  let s = sin(angle);
  let c = cos(angle);
  return vec2<f32>(v.x * c - v.y * s, v.x * s + v.y * c);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) {
    return;
  }

  let uv = vec2<f32>(gid.xy) / dims;
  let mouse = u.zoom_config.yz;
  let time = u.config.x;
  let aspect = dims.x / dims.y;
  let audio = plasmaBuffer[0].xyz;

  let scale = mix(8.0, 38.0, u.zoom_params.x);
  let zoomAmount = mix(1.0, 4.5, u.zoom_params.y);
  let rotation = u.zoom_params.z * 6.28318 + time * 0.25 * (0.2 + audio.y);
  let mouseInfluence = u.zoom_params.w;

  let axial = vec2<f32>(1.7320508, 1.0);
  let uvAspect = vec2<f32>(uv.x * aspect, uv.y);
  let scaled = uvAspect * scale;

  let gridA = (fract(scaled / axial) - 0.5) * axial;
  let idA = floor(scaled / axial);
  let shifted = scaled - axial * 0.5;
  let gridB = (fract(shifted / axial) - 0.5) * axial;
  let idB = floor(shifted / axial);

  let distA = dot(gridA, gridA);
  let distB = dot(gridB, gridB);
  let useB = distB < distA;

  let local = select(gridA, gridB, useB);
  let cellId = select(idA, idB + 0.5, useB);
  let centerScaled = select((idA + 0.5) * axial, (idB + 0.5) * axial + axial * 0.5, useB);
  let centerUV = vec2<f32>(centerScaled.x / scale / aspect, centerScaled.y / scale);

  let mouseVec = (mouse - centerUV) * vec2<f32>(aspect, 1.0);
  let mouseDist = length(mouseVec);
  let influence = (1.0 - smoothstep(0.0, 0.55, mouseDist)) * mouseInfluence;
  let hexMask = 1.0 - smoothstep(0.42, 0.52, length(local));

  let rotLocal = rotate(local, rotation * influence);
  let zoom = mix(1.0, 1.0 / zoomAmount, influence);
  let refractedScaled = centerScaled + rotLocal * zoom;
  let refractedUV = clamp(vec2<f32>(refractedScaled.x / scale / aspect, refractedScaled.y / scale), vec2<f32>(0.0), vec2<f32>(1.0));

  let split = rotate(vec2<f32>(0.006 + 0.010 * audio.z, 0.0), rotation) * influence;
  let sampleR = clamp(refractedUV + split, vec2<f32>(0.0), vec2<f32>(1.0));
  let sampleG = refractedUV;
  let sampleB = clamp(refractedUV - split, vec2<f32>(0.0), vec2<f32>(1.0));

  var finalColor = vec3<f32>(
    textureSampleLevel(readTexture, u_sampler, sampleR, 0.0).r,
    textureSampleLevel(readTexture, u_sampler, sampleG, 0.0).g,
    textureSampleLevel(readTexture, u_sampler, sampleB, 0.0).b
  );

  let rim = smoothstep(0.30, 0.50, length(local)) * hexMask;
  let shimmer = hash32(cellId, time);
  let honeyTint = mix(vec3<f32>(0.12, 0.75, 1.0), vec3<f32>(1.0, 0.45, 0.85), 0.35 + audio.x * 0.4);
  finalColor = finalColor + honeyTint * (rim * (0.18 + 0.18 * shimmer) + influence * 0.10);

  let baseDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, refractedUV, 0.0).r;
  let depthOut = clamp(mix(baseDepth, baseDepth * 0.4 + influence * 0.5, 0.30), 0.0, 1.0);
  let finalAlpha = clamp(0.70 + influence * 0.18 + rim * 0.10, 0.48, 0.98);

  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depthOut, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(influence, hexMask, rim, finalAlpha));
}

fn hash32(p: vec2<f32>, time: f32) -> f32 {
  let h = sin(dot(p, vec2<f32>(91.7, 313.1)) + time * 0.7) * 43758.5453;
  return fract(h);
}
