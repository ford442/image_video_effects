// Sequin Flip — articulated disks with GGX microfacet metal and propagating flip fronts.
// A/C stores tone-mapped display RGBA. B and extraBuffer are unused.
// Premium mixed-eight upgrade: 2026-08-27.

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

const PI: f32 = 3.14159265359;

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) /
               (x * (2.43 * x + 0.59) + 0.14),
               vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn safeCoord(uv: vec2<f32>, resolution: vec2<f32>) -> vec2<i32> {
  return clamp(vec2<i32>(clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)) * resolution),
               vec2<i32>(0), vec2<i32>(resolution) - vec2<i32>(1));
}

fn historyAt(uv: vec2<f32>, resolution: vec2<f32>) -> vec4<f32> {
  return textureLoad(dataTextureC, safeCoord(uv, resolution), 0);
}

fn ggxDistribution(noh: f32, roughness: f32) -> f32 {
  let a2 = roughness * roughness * roughness * roughness;
  let d = noh * noh * (a2 - 1.0) + 1.0;
  return a2 / max(PI * d * d, 0.0001);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = vec2<f32>(gid.xy) / resolution;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let aspectVec = vec2<f32>(aspect, 1.0);
  let p = uv * aspectVec;
  let time = u.config.x;
  let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let held = u.zoom_config.w > 0.5;
  let bass = clamp(plasmaBuffer[0].x, 0.0, 2.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 2.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 2.0);

  let gridScale = mix(12.0, 64.0, u.zoom_params.x);
  let brushRadius = mix(0.045, 0.48, u.zoom_params.y);
  let shine = mix(0.08, 1.0, u.zoom_params.z);
  let goldMix = u.zoom_params.w;
  let rowHeight = 0.8660254;
  var grid = p * gridScale;
  let row = floor(grid.y / rowHeight);
  let odd = fract(row * 0.5) * 2.0;
  grid.x += odd * 0.5;
  let cell = floor(vec2<f32>(grid.x, grid.y / rowHeight));
  let local = vec2<f32>(fract(grid.x) * 2.0 - 1.0, fract(grid.y / rowHeight) * 2.0 - 1.0);
  let centerP = vec2<f32>((cell.x + 0.5 - odd * 0.5) / gridScale, (cell.y + 0.5) * rowHeight / gridScale);
  let centerUV = vec2<f32>(centerP.x / aspect, centerP.y);
  let cellNoise = hash12(cell);

  let pointerDist = length(centerP - mouse * aspectVec);
  let hoverFlip = smoothstep(brushRadius, brushRadius * 0.12, pointerDist);
  let heldFlip = hoverFlip * select(0.25, 1.0, held);
  var clickFlip = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 3.0) {
      let rd = length(centerP - ripple.xy * aspectVec);
      let front = age * (0.28 + bass * 0.09);
      clickFlip += exp(-abs(rd - front) * 44.0) * exp(-age * 0.9);
    }
  }

  let audioTilt = sin(time * (1.5 + mids * 2.4) + cellNoise * 9.0) * mids * 0.12;
  let flip = clamp(heldFlip + clickFlip * 0.9 + bass * 0.04 + audioTilt, 0.0, 1.0);
  let angle = flip * PI;
  let cosAngle = cos(angle);
  let sinAngle = sin(angle);
  let disk = 1.0 - smoothstep(0.88, 0.96, length(local));
  let projectedY = local.y / max(abs(cosAngle), 0.075);
  let visibleDisk = disk * (1.0 - smoothstep(0.86, 0.98, abs(projectedY)));
  let sphereZ = sqrt(max(0.0, 1.0 - local.x * local.x - projectedY * projectedY));
  let microGroove = sin(local.x * 58.0 + cellNoise * 11.0) * sin(projectedY * 47.0 - time * treble * 2.0);
  var normal = normalize(vec3<f32>(local.x + microGroove * 0.035, projectedY + microGroove * 0.025, sphereZ));
  normal = normalize(vec3<f32>(normal.x, normal.y * cosAngle - normal.z * sinAngle, normal.y * sinAngle + normal.z * cosAngle));

  let source = textureSampleLevel(readTexture, u_sampler, clamp(centerUV + vec2<f32>(local.x, projectedY) / gridScale / aspectVec, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let history = historyAt(uv - vec2<f32>(0.0, clickFlip * 0.002), resolution);
  let silver = vec3<f32>(0.72, 0.79, 0.9);
  let gold = vec3<f32>(1.05, 0.62, 0.14);
  let backMetal = mix(silver, gold, goldMix);
  let frontFacing = smoothstep(-0.08, 0.08, cosAngle);
  let baseColor = mix(backMetal, source.rgb, frontFacing);
  let light = normalize(vec3<f32>((mouse.x - 0.5) * 0.9, (mouse.y - 0.5) * 0.9, 1.0));
  let view = vec3<f32>(0.0, 0.0, 1.0);
  let halfVector = normalize(light + view);
  let nol = max(dot(normal, light), 0.0);
  let noh = max(dot(normal, halfVector), 0.0);
  let nov = max(dot(normal, view), 0.0);
  let roughness = mix(0.42, 0.065, shine) * (1.0 - treble * 0.12);
  let distribution = ggxDistribution(noh, max(roughness, 0.035));
  let fresnel = 0.04 + 0.96 * pow(1.0 - noh, 5.0);
  let specular = distribution * fresnel * nol / max(4.0 * nov * max(nol, 0.05), 0.08);
  let sparkle = pow(max(0.0, 0.5 + 0.5 * sin(cellNoise * 91.0 + time * (5.0 + treble * 9.0))), 18.0) * treble;
  var hdrDisk = baseColor * (0.16 + nol * 0.84) + vec3<f32>(specular * shine * 0.42 + sparkle * shine);
  hdrDisk += mix(vec3<f32>(0.12, 0.8, 1.25), vec3<f32>(1.3, 0.2, 0.7), goldMix) * abs(clickFlip) * 0.18;
  hdrDisk = mix(hdrDisk, history.rgb, clamp(0.02 + clickFlip * 0.045, 0.0, 0.08));
  let gapColor = source.rgb * 0.06;
  let hdr = mix(gapColor, hdrDisk, visibleDisk);
  let display = aces(max(hdr, vec3<f32>(0.0)));
  let alpha = clamp(source.a * (0.18 + visibleDisk * 0.82), 0.0, 1.0);
  let result = vec4<f32>(display, alpha);

  textureStore(dataTextureA, coord, result);
  textureStore(writeTexture, coord, result);
  let depth = textureLoad(readDepthTexture, coord, 0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
