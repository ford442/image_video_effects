// ═══════════════════════════════════════════════════════════════════
//  Quantum Liquid-Metal Chronosphere
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-15
//  Ideas: capillary normal modes; chrono shear bands
//  A packing: ACES display RGBA
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
  config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // Fluid Density, Surface Tension, Flow Speed, Iridescence Shift
  ripples: array<vec4<f32>, 50>, // .xy = ripple uv, .z = start time, .w = padding
};

fn rot(a: f32) -> mat2x2<f32> {
  let s = sin(a);
  let c = cos(a);
  return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
  let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
  return mix(b, a, h) - k * h * (1.0 - h);
}

fn hash33(p3_in: vec3<f32>) -> vec3<f32> {
    var p3 = fract(p3_in * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}

// 3D Simplex noise
fn simplex3(p: vec3<f32>) -> f32 {
    let K1 = 0.333333333;
    let K2 = 0.166666667;
    let i = floor(p + (p.x + p.y + p.z) * K1);
    let d0 = p - (i - (i.x + i.y + i.z) * K2);

    let e = step(vec3<f32>(0.0), d0 - d0.yzx);
    let i1 = e * (1.0 - e.zxy);
    let i2 = 1.0 - e.zxy * (1.0 - e);

    let d1 = d0 - (i1 - 1.0 * K2);
    let d2 = d0 - (i2 - 2.0 * K2);
    let d3 = d0 - (1.0 - 3.0 * K2);

    var h = max(0.6 - vec4<f32>(dot(d0, d0), dot(d1, d1), dot(d2, d2), dot(d3, d3)), vec4<f32>(0.0));
    let n = h * h * h * h * vec4<f32>(
        dot(d0, hash33(i) - 0.5),
        dot(d1, hash33(i + i1) - 0.5),
        dot(d2, hash33(i + i2) - 0.5),
        dot(d3, hash33(i + 1.0) - 0.5)
    );
    return dot(n, vec4<f32>(52.0));
}

// Idea 1: coherent quadrupole and octupole capillary modes ride on the
// original simplex-displaced sphere instead of replacing it.
fn capillaryNormalModes(direction: vec3<f32>, time: f32, flowSpeed: f32) -> f32 {
  let y2 = direction.y * direction.y;
  let quadrupole = 0.5 * (3.0 * y2 - 1.0) * cos(time * flowSpeed * 0.83)
    + 0.35 * (direction.x * direction.x - direction.z * direction.z)
      * sin(time * flowSpeed * 0.67);
  let octupole = 0.5 * direction.y * (5.0 * y2 - 3.0)
      * sin(time * flowSpeed * 1.09)
    + 1.5 * direction.x * direction.y * direction.z
      * cos(time * flowSpeed * 0.91);
  return quadrupole * 0.72 + octupole * 0.38;
}

fn map(p_in: vec3<f32>, time: f32) -> f32 {
  let fluidDensity = u.zoom_params.x;
  let surfaceTension = u.zoom_params.y;
  let flowSpeed = u.zoom_params.z;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0));

  // Chronosphere domain folding
  let r = max(length(p_in), 0.0001);
  let radialDirection = p_in / r;
  let chronoDistortion = sin(r * 4.0 - time * flowSpeed) * 0.2;
  var p = p_in + radialDirection * chronoDistortion;

  let capillaryMode = capillaryNormalModes(radialDirection, time, flowSpeed);
  let capillaryAmplitude = (0.035 + 0.025 * surfaceTension)
    * (1.0 + audio.x * 0.18);
  let baseSphere = length(p)
    - (1.5 + chronoDistortion + capillaryMode * capillaryAmplitude);

  let noiseP = p * (1.0 + fluidDensity * 2.0) + time * flowSpeed * 0.5;
  let displacement = simplex3(noiseP) * surfaceTension;

  var d = baseSphere + displacement;

  // Mouse Gravity Well
  if (u.zoom_config.w > 0.5) {
    let mouse_uv = u.zoom_config.yz * 2.0 - 1.0;
    let mouse_ray = normalize(vec3<f32>(mouse_uv, -1.0));
    let t_ray = dot(p, mouse_ray);
    let closest_p = mouse_ray * t_ray;
    let dist_to_ray = length(p - closest_p);
    let pull = exp(-dist_to_ray * 3.0) * 0.8;
    d = smin(d, baseSphere - pull, 0.5);
  }

  return d;
}

fn calcNormal(p: vec3<f32>, time: f32) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.5773 * 0.001;
    return normalize(
        e.xyy * map(p + e.xyy, time) +
        e.yyx * map(p + e.yyx, time) +
        e.yxy * map(p + e.yxy, time) +
        e.xxx * map(p + e.xxx, time)
    );
}

fn palette(t: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.263, 0.416, 0.557);
    return a + b * cos(6.28318 * (c * t + d));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp(
    (x * (a * x + b)) / (x * (c * x + d) + e),
    vec3<f32>(0.0),
    vec3<f32>(1.0)
  );
}

fn luma(color: vec3<f32>) -> f32 {
  return dot(color, vec3<f32>(0.2126, 0.7152, 0.0722));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let coord = vec2<i32>(id.xy);
    let resolution = vec2<f32>(u.config.zw);
    if (f32(coord.x) >= resolution.x || f32(coord.y) >= resolution.y) { return; }

    let uv = (vec2<f32>(coord) - 0.5 * resolution) / resolution.y;
    let time = u.config.x;
    let iridescenceShift = u.zoom_params.w;
    let flowSpeed = u.zoom_params.z;
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0));

    let ro = vec3<f32>(0.0, 0.0, 4.0);
    let rd = normalize(vec3<f32>(uv, -1.0));

    var t = 0.0;
    var d = 0.0;
    var hit = false;
    for(var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        d = map(p, time);
        if (d < 0.001) {
          hit = true;
          break;
        }
        if (t > 10.0) { break; }
        t += d;
    }

    var color = vec3<f32>(0.05, 0.05, 0.06); // Dark void background
    var surfaceAlpha = 0.0;
    var sceneDepth = 1.0;

    if (hit) {
        let p = ro + rd * t;
        let n = calcNormal(p, time);

        let viewDir = normalize(ro - p);
        let ndotv = max(dot(n, viewDir), 0.0);

        // Idea 2: latitude-dependent differential rotation shears the
        // thin-film phase into continuous migrating metallic bands.
        let latitude = asin(clamp(n.y, -1.0, 1.0));
        let longitude = atan2(p.z, p.x);
        let differentialSpin = time * flowSpeed
          * (0.35 + 0.65 * (1.0 - n.y * n.y));
        let shearWave = sin(
          latitude * 11.0 + longitude * 2.0 - differentialSpin * 2.0
            + audio.y * 0.25
        );
        let shearBands = smoothstep(0.55, 0.98, abs(shearWave));
        let shearedFilmPhase = longitude * 0.12 + latitude * 0.35
          + differentialSpin * 0.18 + shearWave * 0.18;

        // Iridescent thin-film interference
        let baseColor = vec3<f32>(0.1, 0.1, 0.15);
        let iridescence = palette(
          ndotv * 2.0 + shearedFilmPhase + iridescenceShift
        );

        // Lighting
        let lightDir = normalize(vec3<f32>(1.0, 1.0, 1.0));
        let diffuse = max(dot(n, lightDir), 0.0);
        let specular = pow(
          max(dot(reflect(-lightDir, n), viewDir), 0.0),
          32.0
        ) * (1.0 + audio.z * 0.3);

        // Fresnel
        let fresnel = pow(1.0 - ndotv, 3.0);

        color = baseColor * diffuse + iridescence * fresnel + vec3<f32>(1.0) * specular;
        color *= mix(0.82, 1.14, shearBands);

        // Ambient Occlusion pseudo
        let ao = clamp(map(p + n * 0.5, time) * 2.0, 0.0, 1.0);
        color *= ao;
        surfaceAlpha = clamp(0.42 + fresnel * 0.42 + shearBands * 0.16, 0.0, 1.0);
        sceneDepth = clamp(t / 10.0, 0.0, 1.0);
    }

    // Ethereal bloom / glow (basic distance based)
    let glow = exp(-t * 0.15) * 0.2 * palette(time * 0.1);
    color += glow;

    let displayColor = acesToneMap(max(color, vec3<f32>(0.0)));
    let alpha = clamp(surfaceAlpha + luma(max(glow, vec3<f32>(0.0))) * 0.35, 0.0, 1.0);
    let display = vec4<f32>(displayColor, alpha);

    textureStore(writeTexture, coord, display);
    textureStore(writeDepthTexture, coord, vec4<f32>(sceneDepth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, display);
}