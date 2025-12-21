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

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let aspect = resolution.x / resolution.y;
  let uv = vec2<f32>(global_id.xy) / resolution;

  // Params
  let intensity = mix(0.1, 1.5, u.zoom_params.x);
  let threshold = mix(0.0, 0.9, u.zoom_params.y);
  let spread = mix(0.1, 2.0, u.zoom_params.z);
  let ghostCount = mix(2.0, 8.0, u.zoom_params.w);

  let mouse = u.zoom_config.yz;

  // Base Image
  var finalColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

  // Lens Flare Generation
  // Light Source is the mouse position
  // We compute the vector from Screen Center (0.5, 0.5) to Mouse.
  // Actually, standard flares happen along the line passing through the light source and the screen center.
  // So if Mouse is Light Source, and we are looking at Pixel UV.
  // We want to draw ghosts at positions along the axis defined by (0.5, 0.5) and Mouse.

  let center = vec2<f32>(0.5, 0.5);
  let axis = center - mouse; // Vector from light to center

  // We need to determine if the current pixel UV is part of a "ghost".
  // A ghost is a blob at some position along the axis.

  // Sample the color AT the mouse position to tint the flare
  let lightColorFull = textureSampleLevel(readTexture, u_sampler, mouse, 0.0).rgb;

  // Apply threshold
  let maxRGB = max(lightColorFull.r, max(lightColorFull.g, lightColorFull.b));
  var lightColor = vec3<f32>(0.0);
  if (maxRGB > threshold) {
      lightColor = lightColorFull * intensity;
  }

  // If the light source (mouse) is dark, no flares.
  // But maybe the user wants to play with it even if dark.
  // Let's ensure a minimum visibility or use a "fake" white light if image is dark?
  // User request: "responsive". If I point at a dark spot, maybe no flare.
  // Let's add a small base value so it's always visible for demo.
  lightColor = max(lightColor, vec3<f32>(0.05));

  // Render Ghosts
  var flareAccum = vec3<f32>(0.0);

  // Ghost vector
  // The ghosts appear at: pos = center + (mouse - center) * scale
  // We iterate scales.

  let ghostStep = 1.0 / ghostCount;

  for (var i = 0.0; i < 8.0; i = i + 1.0) {
      if (i >= ghostCount) { break; }

      // Calculate ghost position
      // Distribute ghosts along the axis
      // Some are behind center, some in front.
      let scale = -1.0 + (i * 0.5); // Range -1.0 to ...
      // Let's use a non-linear distribution
      let offset = axis * (scale * spread);
      let ghostPos = center + offset;

      // Distance from current pixel to ghost center
      // Correct aspect for circular shapes
      let uv_aspect = vec2<f32>((uv.x - 0.5) * aspect + 0.5, uv.y);
      let ghostPos_aspect = vec2<f32>((ghostPos.x - 0.5) * aspect + 0.5, ghostPos.y);

      let d = distance(uv_aspect, ghostPos_aspect);

      // Ghost shape: simple soft circle + slight ring
      let size = 0.05 + 0.1 * sin(i * 123.4); // Randomize sizes
      let softness = 0.02;

      let weight = smoothstep(size + softness, size, d);

      // Chromatic aberration for ghosts (color shift based on index)
      let hueShift = i * 0.5;
      let r = cos(hueShift) * 0.5 + 0.5;
      let g = cos(hueShift + 2.0) * 0.5 + 0.5;
      let b = cos(hueShift + 4.0) * 0.5 + 0.5;
      let ghostColor = vec3<f32>(r, g, b) * lightColor;

      flareAccum = flareAccum + ghostColor * weight * 0.3; // 0.3 opacity
  }

  // Add a "Halo" / Ring
  let haloRadius = length(axis) * 0.5; // Radius depends on distance from center?
  // Standard halo is fixed radius relative to light source?
  // Let's make a ring centered at center? No, centered at light?
  // Usually centered at midpoint?
  // Let's do a ring around the mouse.
  let distToMouse = distance(vec2<f32>(uv.x * aspect, uv.y), vec2<f32>(mouse.x * aspect, mouse.y));
  let ringRadius = 0.3 * spread;
  let ringWidth = 0.02;
  let ring = smoothstep(ringRadius + ringWidth, ringRadius, distToMouse) - smoothstep(ringRadius, ringRadius - ringWidth, distToMouse);
  flareAccum = flareAccum + lightColor * ring * 0.2;

  // Starburst / Rays
  let dirToMouse = normalize(uv - mouse);
  let angle = atan2(dirToMouse.y, dirToMouse.x);
  let ray = max(0.0, sin(angle * 12.0 + u.config.x) * sin(angle * 5.0 - u.config.x * 0.5));
  let rayFalloff = 1.0 / (distToMouse * 10.0 + 0.1);
  flareAccum = flareAccum + lightColor * ray * rayFalloff * 0.2;


  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor + flareAccum, 1.0));
}
