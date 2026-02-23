// ═══════════════════════════════════════════════════════════════
//  Nebula Gyroid - Raymarched generative shader
//  Category: generative
//  Features: raymarched, mouse-driven
//  Description: Ethereal, flowing organic form with iridescent lighting.
//               Move your mouse to interact with the fluid geometry.
//  Author: minimax.ai
// ═══════════════════════════════════════════════════════════════

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

// IQ Palette function for beautiful color gradients
fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
  return a + b * cos(6.28318 * (c * t + d));
}

// Gyroid SDF - the core geometric form
fn sdGyroid(p: vec3<f32>, scale: f32, thickness: f32, bias: f32) -> f32 {
  let sp = p * scale;
  return abs(dot(sin(sp), cos(sp.yzx)) - thickness) / scale - bias;
}

// Smooth minimum for organic blending
fn smin(a: f32, b: f32, k: f32) -> f32 {
  let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
  return mix(b, a, h) - k * h * (1.0 - h);
}

// Scene SDF - combines multiple gyroid layers
fn sceneSDF(p: vec3<f32>, time: f32, mouse: vec2<f32>) -> f32 {
  // Domain warping based on mouse
  var warp = p;
  let mouseInfluence = length(mouse) * 0.5;
  warp += 0.1 * sin(p.yzx * 3.0 + time * 0.5) * mouseInfluence;

  // Multiple gyroid layers for complexity
  let gyroid1 = sdGyroid(warp, 2.5, 0.03, 0.0);
  let gyroid2 = sdGyroid(warp + vec3<f32>(time * 0.1, 0.0, 0.0), 4.0, 0.02, 0.0);
  let gyroid3 = sdGyroid(warp * 1.5 + vec3<f32>(0.0, time * 0.15, 0.0), 6.0, 0.015, 0.0);

  // Blend them together
  var d = smin(gyroid1, gyroid2, 0.1);
  d = smin(d, gyroid3, 0.08);

  return d;
}

// Calculate normal using gradient
fn calcNormal(p: vec3<f32>, time: f32, mouse: vec2<f32>) -> vec3<f32> {
  let e = vec2<f32>(0.001, 0.0);
  return normalize(vec3<f32>(
    sceneSDF(p + e.xyy, time, mouse) - sceneSDF(p - e.xyy, time, mouse),
    sceneSDF(p + e.yxy, time, mouse) - sceneSDF(p - e.yxy, time, mouse),
    sceneSDF(p + e.yyx, time, mouse) - sceneSDF(p - e.yyx, time, mouse)
  ));
}

// Raymarching
fn raymarch(ro: vec3<f32>, rd: vec3<f32>, time: f32, mouse: vec2<f32>) -> f32 {
  var t = 0.0;
  let maxDist = 20.0;

  for (var i: i32 = 0; i < 100; i++) {
    let p = ro + rd * t;
    let d = sceneSDF(p, time, mouse);

    if (d < 0.001) {
      return t;
    }

    if (t > maxDist) {
      break;
    }

    t += d * 0.5;
  }

  return -1.0;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;

  // Parameters
  let colorSpeed = u.zoom_params.x * 2.0;
  let iridescence = u.zoom_params.y;
  let fogDensity = u.zoom_params.z * 0.5 + 0.1;
  let specularPower = mix(32.0, 128.0, u.zoom_params.w);

  // Aspect ratio correction
  let aspect = resolution.x / resolution.y;
  var p = uv * 2.0 - 1.0;
  p.x *= aspect;

  // Camera setup - orbiting camera
  let camPos = vec3<f32>(2.5 * sin(time * 0.2), 1.0 + 0.5 * cos(time * 0.3), 2.5 * cos(time * 0.2));
  let target = vec3<f32>(0.0, 0.0, 0.0);

  // Camera matrix
  let forward = normalize(target - camPos);
  let right = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), forward));
  let up = cross(forward, right);

  let rd = normalize(forward + p.x * right + p.y * up);

  // Adjusted mouse
  let adjustedMouse = (mouse - 0.5) * vec2<f32>(aspect, 1.0);

  // Raymarch
  let t = raymarch(camPos, rd, time, adjustedMouse);

  // Background - deep void with subtle gradient
  var color = vec3<f32>(0.02, 0.02, 0.05);
  color += 0.02 * vec3<f32>(0.5, 0.3, 0.8) * (1.0 - length(p) * 0.5);

  if (t > 0.0) {
    let pos = camPos + rd * t;
    let normal = calcNormal(pos, time, adjustedMouse);

    // Lighting
    let lightDir = normalize(vec3<f32>(1.0, 1.0, 1.0));
    let viewDir = normalize(camPos - pos);
    let halfDir = normalize(lightDir + viewDir);

    // Diffuse
    let diff = max(dot(normal, lightDir), 0.0);

    // Specular
    let spec = pow(max(dot(normal, halfDir), 0.0), specularPower);

    // Fresnel for rim lighting
    let fresnel = pow(1.0 - max(dot(normal, viewDir), 0.0), 3.0);

    // Iridescence based on view angle
    let iriAngle = dot(normal, viewDir);
    let iriColor = palette(
      iriAngle * 2.0 + time * 0.3 * colorSpeed,
      vec3<f32>(0.5, 0.5, 0.5),
      vec3<f32>(0.5, 0.5, 0.5),
      vec3<f32>(1.0, 1.0, 1.0),
      vec3<f32>(0.0, 0.33, 0.67)
    );

    // Combine lighting
    let ambient = 0.1;
    let baseColor = vec3<f32>(0.1, 0.15, 0.2);

    color = baseColor * (ambient + diff * 0.7);
    color += spec * vec3<f32>(1.0, 0.95, 0.9) * 0.8;
    color += fresnel * iriColor * 1.2 * iridescence;
    color += iriColor * 0.3 * iridescence;

    // Distance fog
    let fog = exp(-t * fogDensity);
    color = mix(vec3<f32>(0.02, 0.02, 0.05), color, fog);
  }

  // Vignette
  let vignette = 1.0 - length(p) * 0.4;
  color *= vignette;

  // Tone mapping
  color = color / (color + vec3<f32>(1.0));

  // Gamma correction
  color = pow(color, vec3<f32>(1.0 / 2.2));

  // Write output
  textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));

  // Write depth
  var depth = 0.5;
  if (t > 0.0) {
    depth = 1.0 - (t / 20.0);
  }
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
