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
  config: vec4<f32>,              // time, audioOverall, resolutionX, resolutionY
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

const BALL_COUNT: u32 = 8u;

// Simple Hash for Noise
fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
    var i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i + vec2<f32>(0.0, 0.0)), hash(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash(i + vec2<f32>(0.0, 1.0)), hash(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var shift = vec2<f32>(100.0);
    var p2 = p;
    // Rotate to reduce axial bias
    let rot = mat2x2<f32>(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
    for (var i = 0; i < 3; i = i + 1) {
        v += a * noise(p2);
        p2 = rot * p2 * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
    let k = vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0);
    let p = abs(fract(vec3<f32>(h) + k) * 6.0 - vec3<f32>(3.0));
    return v * mix(vec3<f32>(1.0), clamp(p - vec3<f32>(1.0), vec3<f32>(0.0), vec3<f32>(1.0)), s);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;

  // Sample original image
  let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  // Audio reactivity from canonical plasmaBuffer
  var audioOverall = u.config.y;
  var audioBass = audioOverall * 1.2;
  var audioMid = audioOverall;
  var audioHigh = audioOverall;
  if (arrayLength(&plasmaBuffer) > 0u) {
    let audio = plasmaBuffer[0];
    audioBass = audio.x;
    audioMid = audio.y;
    audioHigh = audio.z;
    audioOverall = (audio.x + audio.y + audio.z) * 0.3333;
  }
  let audioReactivity = 1.0 + audioOverall * 0.5;

  // Plasma Calculation
  var plasmaField = 0.0;
  var plasmaColor = vec3<f32>(0.0);
  var shadowVal = 0.0;

  let time = u.config.x;
  let aspect = resolution.x / resolution.y;

  // Iterate procedural plasma balls
  for (var i = 0u; i < BALL_COUNT; i = i + 1u) {
      let fi = f32(i);
      // Procedural orbital motion
      let angle = time * 0.3 + fi * 0.785398;
      let radiusOrbit = 0.25 + 0.12 * sin(time * 0.17 + fi * 0.63);
      var pos = vec2<f32>(
          0.5 + radiusOrbit * cos(angle),
          0.5 + radiusOrbit * sin(angle) * 0.6
      );
      // Audio reactive pulse
      let radius = 0.045 + 0.025 * sin(time * 1.5 + fi) + 0.015 * audioBass;
      let ballColor = hsv2rgb(fract(0.12 * fi + time * 0.05), 0.85, 1.0);

      if (radius > 0.0) {
          // Correct aspect ratio for distance
          let dvec = (uv - pos) * vec2<f32>(aspect, 1.0);
          let dist = length(dvec);

          // Velocity-derived trail direction
          let nextPos = vec2<f32>(
              0.5 + radiusOrbit * cos(angle + 0.01),
              0.5 + radiusOrbit * sin(angle + 0.01) * 0.6
          );
          let vel = nextPos - pos;
          let velDir = normalize(vel + vec2<f32>(0.0001));
          let speed = length(vel);

          // Wisp/Noise distortion
          let noiseVal = fbm(uv * 20.0 - vel * time * 8.0 * audioReactivity + vec2<f32>(fi * 12.34));

          // Trail behind velocity
          let dotP = dot(normalize(dvec), velDir);
          let trail = smoothstep(0.2, 1.0, -dotP);

          // Irregular whooshing
          let distortion = 1.0 + (1.5 * noiseVal * trail) + (0.5 * noiseVal);
          let effectiveRadius = radius * distortion;

          // Metaball influence
          let influence = exp(-40.0 * (dist * dist) / (effectiveRadius * effectiveRadius));

          plasmaField += influence;
          plasmaColor += ballColor * influence * 1.5;

          // Shadow logic
          let lightDir = normalize(vec2<f32>(-1.0, -1.0));
          let shadowOffset = vec2<f32>(0.01, 0.01);
          let shadowUV = uv - shadowOffset;
          let dvecShadow = (shadowUV - pos) * vec2<f32>(aspect, 1.0);
          let distShadow = length(dvecShadow);
          let shadowInfluence = exp(-100.0 * (distShadow * distShadow) / (radius * radius));
          shadowVal += shadowInfluence;
      }
  }

  // Resolve Plasma
  var finalColor = baseColor.rgb;

  // Apply Shadow first (on the image)
  let shadowStr = smoothstep(0.1, 1.0, shadowVal);
  finalColor = mix(finalColor, finalColor * 0.5, shadowStr * 0.8);

  // Render Plasma on top
  if (plasmaField > 0.1) {
      // Normalize color
      let renderColor = plasmaColor / plasmaField;

      // Add core glow
      let core = smoothstep(0.8, 2.0, plasmaField);
      let edge = smoothstep(0.1, 0.8, plasmaField);

      let wispColor = renderColor;
      let coreColor = vec3<f32>(1.0, 1.0, 1.0);

      let plasmaFinal = mix(wispColor, coreColor, core);

      let alpha = clamp(plasmaField, 0.0, 1.0);
      finalColor = mix(finalColor, plasmaFinal, alpha);
  }

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, 1.0));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(finalColor, 1.0));

  // Preserve depth
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(0.0));
}
