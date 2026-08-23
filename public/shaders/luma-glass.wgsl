// ═══════════════════════════════════════════════════════════════════
//  Luma Glass — Luminance-Driven Refraction & Sellmeier Dispersion
//  Category: distortion
//  Features: mouse-driven, audio-reactive, depth-thickness,
//            sellmeier-dispersion, caustic-trace, fresnel, semantic-alpha, ACES
//  Complexity: High
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
  zoom_params: vec4<f32>,  // x=RefractionDepth, y=SurfaceSmoothness, z=SpecularShine, w=LightDistance
  ripples: array<vec4<f32>, 50>,
};

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn luminance(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let pixel = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let texel = vec2<f32>(1.0 / resolution.x, 1.0 / resolution.y);
  let rawMouse = u.zoom_config.yz;
  let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
  let aspect = resolution.x / max(resolution.y, 1.0);
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Critically damped spring cursor in extraBuffer[133..138]
  let isWriter = (global_id.x == 0u && global_id.y == 0u);
  let hasState = (arrayLength(&extraBuffer) > 138u);

  var mouse = rawMouse;
  if (hasState && extraBuffer[138] > 0.5) {
    mouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  }

  if (isWriter && hasState) {
    let lastTime = extraBuffer[137];
    let dt = clamp(time - lastTime, 0.0, 0.05);
    var sPos = mouse;
    var sVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[138] < 0.5) {
      sPos = rawMouse;
      sVel = vec2<f32>(0.0);
    }
    let stiffness = 45.0;
    let damping = 13.416; // 2 * sqrt(45)
    let accel = (rawMouse - sPos) * stiffness - sVel * damping;
    sVel += accel * dt;
    sPos += sVel * dt;
    extraBuffer[133] = sPos.x;
    extraBuffer[134] = sPos.y;
    extraBuffer[135] = sVel.x;
    extraBuffer[136] = sVel.y;
    extraBuffer[137] = time;
    extraBuffer[138] = 1.0;
  }

  // Exact parameter contracts
  let refractBase = u.zoom_params.x * (1.0 + bass * 0.25);
  let smoothness = u.zoom_params.y;
  let specularShine = u.zoom_params.z * (1.0 + treble * 0.3);
  let lightDistance = u.zoom_params.w;

  let mouseDeform = (mouse - uv) * (0.15 + held * 0.1);
  let deformUV = uv + mouseDeform * smoothness;

  let uvT = clamp(deformUV + vec2<f32>(0.0, -texel.y), vec2<f32>(0.001), vec2<f32>(0.999));
  let uvB = clamp(deformUV + vec2<f32>(0.0,  texel.y), vec2<f32>(0.001), vec2<f32>(0.999));
  let uvL = clamp(deformUV + vec2<f32>(-texel.x, 0.0), vec2<f32>(0.001), vec2<f32>(0.999));
  let uvR = clamp(deformUV + vec2<f32>( texel.x, 0.0), vec2<f32>(0.001), vec2<f32>(0.999));

  let sT = textureSampleLevel(readTexture, u_sampler, uvT, 0.0);
  let sB = textureSampleLevel(readTexture, u_sampler, uvB, 0.0);
  let sL = textureSampleLevel(readTexture, u_sampler, uvL, 0.0);
  let sR = textureSampleLevel(readTexture, u_sampler, uvR, 0.0);

  let lumaT = luminance(sT.rgb);
  let lumaB = luminance(sB.rgb);
  let lumaL = luminance(sL.rgb);
  let lumaR = luminance(sR.rgb);

  let dX = lumaR - lumaL;
  let dY = lumaB - lumaT;

  // Click ripple shocks
  let rippleCount = min(u32(u.config.y), 50u);
  var rippleNormal = vec2<f32>(0.0);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let age = time - r.z;
    if (age >= 0.0 && age < 2.0) {
      let rDist = length((uv - r.xy) * vec2<f32>(aspect, 1.0));
      let wave = cos((rDist - age * 0.5) * 35.0) * exp(-rDist * 3.5) * exp(-age * 1.4);
      let rDir = normalize(uv - r.xy + vec2<f32>(0.0001));
      rippleNormal += rDir * wave * 0.05;
    }
  }

  let surfaceNormal = normalize(vec3<f32>(
    -dX * mix(50.0, 10.0, smoothness) + rippleNormal.x * 20.0,
    -dY * mix(50.0, 10.0, smoothness) + rippleNormal.y * 20.0,
    1.0
  ));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let glassThickness = depth * (0.5 + refractBase);
  let nGlass = 1.45 + lumaT * 0.35 + bass * 0.1;
  let nAir = 1.0;

  var spectralColor = vec3<f32>(0.0);
  let wavelengths = array<f32, 7>(650.0, 610.0, 570.0, 530.0, 470.0, 440.0, 400.0);
  let spectralWeights = array<f32, 7>(0.10, 0.13, 0.16, 0.18, 0.16, 0.15, 0.12);

  for (var i: i32 = 0; i < 7; i = i + 1) {
    let wl = wavelengths[i];
    let nDisp = nGlass + 0.02 * (1.0 - wl / 550.0);
    let etaDisp = nAir / nDisp;
    let refractDir = refract(vec3<f32>(0.0, 0.0, -1.0), surfaceNormal, etaDisp);
    let offset = refractDir.xy * refractBase * 0.06 * glassThickness;
    let sampleUV = clamp(deformUV + offset, vec2<f32>(0.001), vec2<f32>(0.999));
    let samp = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
    spectralColor += samp * spectralWeights[i];
  }

  let pixelPos = vec3<f32>(uv.x * aspect, uv.y, 0.0);
  let lightPos = vec3<f32>(mouse.x * aspect, mouse.y, 0.25 + lightDistance * 1.2);
  let lightDir = normalize(lightPos - pixelPos);
  let viewDir = vec3<f32>(0.0, 0.0, 1.0);
  let halfDir = normalize(lightDir + viewDir);
  let specular = pow(max(dot(surfaceNormal, halfDir), 0.0), mix(12.0, 96.0, specularShine));
  let fresnel = pow(1.0 - max(dot(surfaceNormal, viewDir), 0.0), 3.0);

  let caustic = pow(max(dot(surfaceNormal, lightDir), 0.0), 4.0) * glassThickness * (0.3 + bass * 0.3);
  let sss = vec3<f32>(0.15, 0.35, 0.65) * glassThickness * lumaT * 0.25;

  let lumaBase = luminance(spectralColor);
  let tint = mix(
    vec3<f32>(1.0),
    vec3<f32>(lumaBase, lumaBase * (0.82 + mids * 0.08), 1.0 - lumaBase * 0.3 + treble * 0.1),
    0.3 + specularShine * 0.5
  );
  let shimmer = vec3<f32>(0.2, 0.5 + treble * 0.1, 0.8) * specular * (0.5 + bass * 0.5);
  var color = spectralColor * tint + shimmer + fresnel * 0.18 + caustic + sss;

  // Exact dataTextureC persistence
  let prevC = textureLoad(dataTextureC, pixel, 0).rgb;
  color = mix(color, prevC, 0.08);

  let finalRGB = aces(color);

  let alpha = clamp(glassThickness * fresnel * depth * 0.8 + specular * 0.2 + bass * 0.05 + 0.35, 0.1, 1.0);
  let depthOut = clamp(depth + fresnel * 0.05, 0.0, 1.0);
  let finalPixel = vec4<f32>(finalRGB, alpha);

  textureStore(writeTexture, pixel, finalPixel);
  textureStore(dataTextureA, pixel, finalPixel);
  textureStore(writeDepthTexture, pixel, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
}
