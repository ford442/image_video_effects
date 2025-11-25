@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;

struct Uniforms {
  config: vec4<f32>,              // time, rippleCount, resolutionX, resolutionY
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,  // x, y, startTime, unused
};

@group(0) @binding(3) var<uniform> u: Uniforms;

struct PlasmaBall {
    pos: vec4<f32>,   // x, y, vx, vy
    color: vec4<f32>, // r, g, b, radius
    info: vec4<f32>,  // age, maxAge, seed, unused
};

@group(0) @binding(12) var<storage, read> plasmaBalls: array<PlasmaBall, 50>;

// Simple Hash for Noise
fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;

  // Sample original image
  let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  // Plasma Calculation
  var plasmaField = 0.0;
  var plasmaColor = vec3<f32>(0.0);
  var shadowVal = 0.0;

  // Iterate balls
  for (var i = 0u; i < 50u; i = i + 1u) {
      let ball = plasmaBalls[i];
      // Check if active (age < maxAge and radius > 0)
      if (ball.info.x < ball.info.y && ball.color.w > 0.0) {
          let pos = ball.pos.xy;
          // Correct aspect ratio for distance
          let aspect = resolution.x / resolution.y;
          let dvec = (uv - pos) * vec2<f32>(aspect, 1.0);
          let dist = length(dvec);

          let radius = ball.color.w;

          // Wisp/Noise distortion
          // Displace distance based on noise and velocity direction
          let vel = ball.pos.zw;
          let velDir = normalize(vel);
          let speed = length(vel);
          let time = u.config.x;

          // Noise offset
          // Animate noise with time and velocity
          // Increased frequency and speed for more chaos
          let noiseVal = fbm(uv * 20.0 - vel * time * 8.0 + vec2<f32>(ball.info.z));

          // Distort the field
          // Make it trail behind significantly
          // dot(dvec, vel) is positive if we are in front, negative if behind
          let dotP = dot(normalize(dvec), velDir);
          let trail = smoothstep(0.2, 1.0, -dotP); // 1.0 behind

          // "Irregular whooshing"
          // Stretch noise along velocity
          // Increase effective radius more dramatically based on noise
          let distortion = 1.0 + (1.5 * noiseVal * trail) + (0.5 * noiseVal);
          let effectiveRadius = radius * distortion;

          // Metaball function: 1 / (dist^2) or similar gaussian
          // Using Gaussian for smoothness: exp(-k * dist^2)
          // Lower k for broader, softer blobs
          let influence = exp(-40.0 * (dist * dist) / (effectiveRadius * effectiveRadius));

          plasmaField += influence;
          // Boost color intensity
          plasmaColor += ball.color.rgb * influence * 1.5;

          // Shadow Logic
          // If pixel is "offset" from ball center away from light, cast shadow
          // Let's assume light is top-left (-1, -1) direction
          let lightDir = normalize(vec2<f32>(-1.0, -1.0));
          let shadowOffset = vec2<f32>(0.01, 0.01); // Shift shadow
          let shadowUV = uv - shadowOffset;
          let dvecShadow = (shadowUV - pos) * vec2<f32>(aspect, 1.0);
          let distShadow = length(dvecShadow);
          let shadowInfluence = exp(-100.0 * (distShadow * distShadow) / (radius*radius));
          shadowVal += shadowInfluence;
      }
  }

  // Resolve Plasma
  var finalColor = baseColor.rgb;

  // Apply Shadow first (on the image)
  // Shadow is just darkening where plasma *would be* if shifted
  // But we only want shadow if there isn't plasma *there* already covering it?
  // Or just multiply.
  // We assume plasma is floating above.
  let shadowStr = smoothstep(0.1, 1.0, shadowVal);
  finalColor = mix(finalColor, finalColor * 0.5, shadowStr * 0.8);

  // Render Plasma on top
  if (plasmaField > 0.1) {
      // Normalize color
      let renderColor = plasmaColor / plasmaField; // weighted average

      // Add "core" glow
      let core = smoothstep(0.8, 2.0, plasmaField);
      let edge = smoothstep(0.1, 0.8, plasmaField);

      // Mix edge and core
      // Edge is "wispy"
      let wispColor = renderColor;
      let coreColor = vec3<f32>(1.0, 1.0, 1.0); // White hot core

      let plasmaFinal = mix(wispColor, coreColor, core);

      // Additive blending or alpha blending?
      // Alpha blending
      let alpha = clamp(plasmaField, 0.0, 1.0);
      finalColor = mix(finalColor, plasmaFinal, alpha);
  }

  textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));

  // Preserve depth (or update if we wanted the balls to have depth)
  // For now, just pass through or 0.0
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(0.0));
}
