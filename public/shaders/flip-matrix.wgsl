// Flip Matrix — inertial split-flap propagation with hinge and bevel mechanics.
// A/C stores ACES display RGBA. B is unused. Source depth passes through.

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

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(91.7, 271.9))) * 43758.5453);
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
  let density = 9.0 + u.zoom_params.x * 54.0;
  let effectRadius = 0.08 + u.zoom_params.y * 0.82;
  let flipIntensity = 0.25 + u.zoom_params.z * 2.75;
  let gap = 0.025 + u.zoom_params.w * 0.24;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0));
  let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let held = u.zoom_config.w > 0.5;

  let grid = vec2<f32>(uv.x * aspect, uv.y) * density;
  let cellId = floor(grid);
  let local = fract(grid);
  let cellCenterAspect = (cellId + 0.5) / density;
  let cellCenter = vec2<f32>(cellCenterAspect.x / aspect, cellCenterAspect.y);
  let mouseDistance = length((cellCenter - mouse) * aspectVec);
  let hoverArrival = mouseDistance / (0.5 + audio.y * 0.08);
  let hoverAge = fract(time * 0.42 - hoverArrival);
  let hoverEnvelope = smoothstep(effectRadius, 0.0, mouseDistance) * exp(-hoverAge * 2.1);
  let heldDrive = select(0.0, smoothstep(effectRadius, 0.0, mouseDistance), held);

  var updateWave = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 3.2) {
      let rd = length((cellCenter - ripple.xy) * aspectVec);
      let arrival = age - rd / (0.32 + audio.x * 0.08);
      if (arrival >= 0.0) {
        updateWave += exp(-arrival * 1.35) * sin(arrival * (18.0 + audio.z * 4.0)) * exp(-rd * 0.8);
      }
    }
  }

  let phaseJitter = (hash21(cellId) - 0.5) * 0.22;
  let inertialAngle = (hoverEnvelope * sin(hoverAge * PI * 2.0) + heldDrive * sin(time * (7.0 + audio.x * 2.0)) * 0.45 + updateWave) * PI * flipIntensity + phaseJitter;
  let cosineAngle = cos(inertialAngle);
  let sineAngle = sin(inertialAngle);
  let projectedHeight = max(abs(cosineAngle), 0.025);
  let sourceLocalY = (local.y - 0.5) / projectedHeight + 0.5;
  let inside = sourceLocalY >= gap && sourceLocalY <= 1.0 - gap && local.x >= gap && local.x <= 1.0 - gap;

  var hdr = vec3<f32>(0.008, 0.01, 0.014);
  var coverage = 0.0;
  if (inside) {
    let sampleLocalY = select(sourceLocalY, 1.0 - sourceLocalY, cosineAngle < 0.0);
    let sampleUV = clamp(vec2<f32>((cellId.x + local.x) / density / aspect, (cellId.y + sampleLocalY) / density), vec2<f32>(0.0), vec2<f32>(1.0));
    let source = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
    let frontMaterial = source.rgb * (0.32 + 0.68 * projectedHeight);
    let backMaterial = mix(source.bgr * 0.14, vec3<f32>(0.11, 0.035, 0.018), 0.68);
    hdr = select(frontMaterial, backMaterial, cosineAngle < 0.0);

    let seam = 1.0 - smoothstep(0.006, 0.035, abs(sourceLocalY - 0.5));
    let edgeDistance = min(min(local.x - gap, 1.0 - gap - local.x), min(sourceLocalY - gap, 1.0 - gap - sourceLocalY));
    let bevel = smoothstep(0.0, 0.075, edgeDistance);
    let hinge = exp(-abs(sourceLocalY - 0.5) * 85.0);
    let normal = normalize(vec3<f32>(0.0, sineAngle, cosineAngle));
    let lightDirection = normalize(vec3<f32>(-0.45, -0.6, 0.85));
    let diffuse = 0.25 + 0.75 * max(dot(normal, lightDirection), 0.0);
    let specular = pow(max(dot(reflect(-lightDirection, normal), vec3<f32>(0.0, 0.0, 1.0)), 0.0), 28.0);
    hdr *= diffuse * (0.58 + bevel * 0.42) * (1.0 - seam * 0.72);
    hdr += vec3<f32>(0.8, 0.86, 0.95) * specular * (0.35 + audio.z * 0.35);
    hdr += vec3<f32>(0.12, 0.07, 0.025) * hinge * (0.4 + abs(sineAngle));
    coverage = source.a * (0.45 + projectedHeight * 0.55) * smoothstep(0.0, 0.04, edgeDistance);
  }

  let history = historyAt(uv, resolution);
  hdr += history.rgb * clamp(abs(updateWave) * 0.035 + hoverEnvelope * 0.015, 0.0, 0.07);
  let alpha = clamp(coverage + abs(updateWave) * 0.12 + heldDrive * 0.08, 0.0, 1.0);
  let result = vec4<f32>(aces(max(hdr, vec3<f32>(0.0))), alpha);
  textureStore(writeTexture, coord, result);
  textureStore(dataTextureA, coord, result);
  let depth = textureLoad(readDepthTexture, coord, 0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
