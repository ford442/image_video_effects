// Dynamic Lens Flares — optical train ghost elements, internal reflection halo, diffraction rays, and chromatic dispersion.
// A/C stores ACES display RGBA for continuous phosphor persistence; B is unused; depth passes through source depth.

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

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) /
               (x * (2.43 * x + 0.59) + 0.14),
               vec3<f32>(0.0), vec3<f32>(1.0));
}

fn historyAt(uv: vec2<f32>, resolution: vec2<f32>) -> vec4<f32> {
  let hi = vec2<i32>(resolution) - vec2<i32>(1);
  let coord = clamp(vec2<i32>(clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)) * resolution), vec2<i32>(0), hi);
  return textureLoad(dataTextureC, coord, 0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / resolution;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let aspectVec = vec2<f32>(aspect, 1.0);
  let time = u.config.x;

  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0));
  let bass = audio.x;
  let mids = audio.y;
  let treble = audio.z;

  let intensity = (0.2 + u.zoom_params.x * 2.2) * (1.0 + bass * 0.45);
  let threshold = 0.1 + u.zoom_params.y * 0.75;
  let spread = 0.2 + u.zoom_params.z * 1.8;
  let ghostCount = 3.0 + u.zoom_params.w * 5.0;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let sourceColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  let rawMouse = u.zoom_config.yz;
  let hasMouse = rawMouse.x >= 0.0 && rawMouse.x <= 1.0 && rawMouse.y >= 0.0 && rawMouse.y <= 1.0;
  let mouse = select(vec2<f32>(0.5, 0.5), rawMouse, hasMouse);
  let held = u.zoom_config.w > 0.5;

  // Click ripple interaction
  var rippleOffset = vec2<f32>(0.0);
  var rippleBurst = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var r = 0u; r < rippleCount; r = r + 1u) {
    let ripple = u.ripples[r];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 2.5) {
      let rDelta = (uv - ripple.xy) * aspectVec;
      let rd = length(rDelta);
      let front = age * (0.32 + bass * 0.12);
      let wave = sin((rd - front) * 60.0) * exp(-abs(rd - front) * 26.0) * exp(-age * 1.1);
      rippleOffset += rDelta / max(rd, 0.0001) * wave * 0.02;
      rippleBurst += abs(wave) * 0.25;
    }
  }

  // Optical axis from light source (mouse) through image center
  let center = vec2<f32>(0.5, 0.5);
  let axis = center - mouse;

  // Sample light source color at mouse position
  let lightColorFull = textureSampleLevel(readTexture, u_sampler, mouse, 0.0).rgb;
  let maxRGB = max(lightColorFull.r, max(lightColorFull.g, lightColorFull.b));
  let lumaHot = smoothstep(threshold, threshold + 0.25, maxRGB);
  let baseLightColor = mix(vec3<f32>(1.0, 0.92, 0.78), lightColorFull, 0.65);
  let lightColor = baseLightColor * (0.2 + lumaHot * 0.8) * intensity;

  var flareAccum = vec3<f32>(0.0);

  // Render optical ghosts along the axis
  let maxGhosts = 8;
  for (var i = 0; i < maxGhosts; i = i + 1) {
    if (f32(i) >= ghostCount) { break; }
    let fi = f32(i);
    let scale = -0.8 + fi * (0.35 * spread);
    let ghostPos = center + axis * scale + rippleOffset;
    let clampedGhostPos = clamp(ghostPos, vec2<f32>(0.0), vec2<f32>(1.0));

    let d = length((uv - clampedGhostPos) * aspectVec);
    let size = (0.04 + 0.06 * sin(fi * 1.8 + time * 0.3)) * (1.0 + mids * 0.25);
    let softness = 0.02 + 0.015 * fi;
    let weight = smoothstep(size + softness, size * 0.2, d);

    // Multi-spectral chromatic dispersion on ghost elements
    let hue = fi * 0.75 + time * 0.1;
    let ghostSpectral = vec3<f32>(
      cos(hue) * 0.5 + 0.5,
      cos(hue + 2.094) * 0.5 + 0.5,
      cos(hue + 4.188) * 0.5 + 0.5
    );

    let ringD = abs(d - size * 0.75);
    let ringGlow = exp(-ringD * 80.0) * 0.4;

    flareAccum += (ghostSpectral * 0.7 + baseLightColor * 0.3) * lightColor * (weight + ringGlow) * 0.45;
  }

  // Internal reflection halo ring
  let distToLight = length((uv - mouse) * aspectVec);
  let haloRadius = (0.22 + length(axis) * 0.25) * spread * select(1.0, 1.3, held);
  let haloWidth = 0.018 + 0.008 * sin(time * 2.0);
  let haloRing = smoothstep(haloRadius + haloWidth, haloRadius, distToLight) -
                 smoothstep(haloRadius, haloRadius - haloWidth, distToLight);
  let haloDispersion = vec3<f32>(
    smoothstep(haloRadius + haloWidth * 1.3, haloRadius, distToLight),
    haloRing,
    smoothstep(haloRadius, haloRadius - haloWidth * 1.3, distToLight)
  );
  flareAccum += lightColor * haloDispersion * 0.35;

  // Starburst diffraction rays from aperture blades
  let toMouse = (uv - mouse) * aspectVec;
  let safeMouseLen = max(length(toMouse), 0.0001);
  let dirToMouse = toMouse / safeMouseLen;
  let angle = atan2(dirToMouse.y, dirToMouse.x);
  let rayBlades = max(0.0, sin(angle * 8.0 + time * (1.0 + treble * 0.8)) * sin(angle * 6.0 - time * 0.5));
  let rayFalloff = 1.0 / (distToLight * 12.0 + 0.12);
  let rayLight = pow(rayBlades, 2.0) * rayFalloff * (0.35 + treble * 0.35);
  flareAccum += lightColor * rayLight * 0.3;

  // Center core glow
  let coreGlow = exp(-distToLight * distToLight * 35.0) * intensity * (0.6 + bass * 0.4);
  flareAccum += baseLightColor * coreGlow * 0.8;

  // Exact previous frame history load for phosphor decay
  let history = historyAt(uv - rippleOffset * 0.5, resolution);

  var hdr = sourceColor.rgb + flareAccum + vec3<f32>(rippleBurst);
  hdr += history.rgb * 0.055;

  let flareLuma = dot(flareAccum, vec3<f32>(0.2126, 0.7152, 0.0722));
  let finalAlpha = clamp(sourceColor.a * 0.5 + flareLuma * 0.5 + rippleBurst * 0.1, 0.0, 1.0);

  let result = vec4<f32>(aces(max(hdr, vec3<f32>(0.0))), finalAlpha);

  textureStore(writeTexture, coord, result);
  textureStore(dataTextureA, coord, result);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
