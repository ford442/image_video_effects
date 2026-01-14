// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=unused, y=MouseX, z=MouseY, w=unused
  zoom_params: vec4<f32>,  // x=DotSize, y=Angle, z=RevealRadius, w=Magnification
  ripples: array<vec4<f32>, 50>,
};

fn rotate(v: vec2<f32>, a: f32) -> vec2<f32> {
    let s = sin(a);
    let c = cos(a);
    return vec2<f32>(v.x * c - v.y * s, v.x * s + v.y * c);
}

fn luminance(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;

  let dotSize = mix(5.0, 50.0, u.zoom_params.x);
  let angle = u.zoom_params.y * 1.57; // 0 to PI/2
  let radius = mix(0.1, 0.4, u.zoom_params.z);
  let mag = mix(1.0, 2.0, u.zoom_params.w);
  let mouse = u.zoom_config.yz;

  // 1. Calculate Halftone
  // We work in screen pixels for consistent dots
  let pixelPos = vec2<f32>(global_id.xy);
  // Rotate coordinates for halftone angle
  let rotPos = rotate(pixelPos, angle);

  // Grid
  let grid = floor(rotPos / dotSize);
  let cellCenter = (grid + 0.5) * dotSize;

  // Un-rotate to get UV to sample intensity
  let samplePos = rotate(cellCenter, -angle);
  let sampleUV = samplePos / resolution;

  let intensity = luminance(textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb);

  // Dot distance in rotated space
  let distToCenter = length(rotPos - cellCenter);
  // Max radius is dotSize / 2 * sqrt(2) for full coverage, effectively dotSize/2 is touching
  let maxR = dotSize * 0.7;
  let dotR = maxR * sqrt(intensity); // Sqrt for area correction

  let dotMask = smoothstep(dotR, dotR - 1.0, distToCenter);
  let halftoneColor = vec3<f32>(dotMask); // White dots on black

  // Invert for "newspaper" look: Black dots on white
  // halftoneColor = vec3<f32>(1.0 - dotMask);
  // Actually let's do CMYK style or just colored dots?
  // Let's do simple: Color = SampleColor * dotMask
  let sampledColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
  let halftoneFinal = sampledColor * dotMask;

  // 2. Calculate Reveal
  let dist = distance(uv, mouse);

  // Magnification lens
  var revealUV = uv;
  if (mag > 1.0) {
      // Distort UV near mouse
      let v = uv - mouse;
      // Simple bulge
      let factor = smoothstep(radius, 0.0, dist);
      revealUV = mouse + v * mix(1.0, 1.0/mag, factor);
  }

  let realColor = textureSampleLevel(readTexture, u_sampler, revealUV, 0.0).rgb;

  let mask = smoothstep(radius, radius - 0.05, dist);

  let finalColor = mix(halftoneFinal, realColor, mask);

  textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
