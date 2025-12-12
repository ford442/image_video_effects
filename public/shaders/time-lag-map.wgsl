// Time-Lag Map - Temporal Delay Buffer
// Per-pixel time delay creating echo and smear effects

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // history buffer 1
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>; // history buffer 2
@group(0) @binding(9) var dataTextureC: texture_2d<f32>; // read history
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=unused, y=MouseX, z=MouseY, w=unused
  zoom_params: vec4<f32>,  // x=BufferLength, y=MappingFunction, z=FeedbackMix, w=MotionSense
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const MAX_LAG: f32 = 1.0;

// Noise function
fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
  p3 = p3 + dot(p3, vec3<f32>(p3.y + 33.33, p3.z + 33.33, p3.x + 33.33));
  return fract((p3.x + p3.y) * p3.z);
}

fn fbm(p: vec2<f32>, time: f32) -> f32 {
  var value = 0.0;
  var amplitude = 0.5;
  var freq = 1.0;
  for (var i = 0; i < 4; i = i + 1) {
    value = value + amplitude * hash21(p * freq + vec2<f32>(time * 0.1));
    freq = freq * 2.0;
    amplitude = amplitude * 0.5;
  }
  return value;
}

// Different lag mapping functions
fn getLagAmount(uv: vec2<f32>, mappingType: f32, time: f32, depth: f32) -> f32 {
  let selector = floor(mappingType * 5.0);
  
  var lag = 0.0;
  
  if (selector < 1.0) {
    // Radial - center is present, edges are past
    let center = vec2<f32>(0.5);
    lag = length(uv - center) * 2.0;
  }
  else if (selector < 2.0) {
    // Horizontal wipe
    lag = uv.x;
  }
  else if (selector < 3.0) {
    // Vertical wipe
    lag = uv.y;
  }
  else if (selector < 4.0) {
    // Spiral delay
    let centered = uv - vec2<f32>(0.5);
    let angle = atan2(centered.y, centered.x) / PI * 0.5 + 0.5;
    let radius = length(centered) * 2.0;
    lag = fract(angle + radius + time * 0.2);
  }
  else {
    // Noise-based organic delay
    lag = fbm(uv * 4.0, time);
  }
  
  // Modulate by depth - foreground is more present
  lag = lag * (1.0 - depth * 0.5);
  
  return clamp(lag, 0.0, 1.0);
}

// Motion detection
fn getMotion(uv: vec2<f32>, texelSize: vec2<f32>) -> f32 {
  // Compare current with history
  let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let history = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).rgb;
  
  return length(current - history);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w));
  let coord = gid.xy;
  if (coord.x >= size.x || coord.y >= size.y) { return; }
  
  let uv = vec2<f32>(f32(coord.x), f32(coord.y)) / vec2<f32>(f32(size.x), f32(size.y));
  let texelSize = 1.0 / vec2<f32>(f32(size.x), f32(size.y));
  let time = u.config.x;
  let frame = u.config.y;
  
  // Parameters
  let bufferLength = mix(0.1, 1.0, u.zoom_params.x);
  let mappingFunction = u.zoom_params.y;
  let feedbackMix = mix(0.0, 0.95, u.zoom_params.z);
  let motionSense = mix(0.0, 2.0, u.zoom_params.w);
  
  // Get depth
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  
  // Calculate per-pixel lag
  var lagAmount = getLagAmount(uv, mappingFunction, time, depth);
  
  // Mouse influence - create lag ripples
  let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
  let toMouse = uv - mouse;
  let mouseDist = length(toMouse);
  let mouseRadius = 0.2;
  
  if (mouseDist < mouseRadius) {
    let mouseInfluence = 1.0 - mouseDist / mouseRadius;
    lagAmount = mix(lagAmount, 1.0, mouseInfluence * 0.5);
  }
  
  // Ripple-based lag disturbance
  for (var i = 0; i < 50; i = i + 1) {
    let ripple = u.ripples[i];
    if (ripple.z > 0.0) {
      let rippleAge = time - ripple.z;
      if (rippleAge > 0.0 && rippleAge < 3.0) {
        let dist = length(uv - ripple.xy);
        let wave = sin(dist * 20.0 - rippleAge * 5.0) * 0.5 + 0.5;
        let fade = 1.0 - rippleAge / 3.0;
        if (dist < rippleAge * 0.3) {
          lagAmount = mix(lagAmount, wave, fade * 0.3);
        }
      }
    }
  }
  
  // Read current frame and history
  let currentColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let historyColor = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
  
  // Motion detection for adaptive delay
  let motion = getMotion(uv, texelSize);
  
  // Adjust lag based on motion - high motion = less lag for responsiveness
  if (motionSense > 0.0) {
    let motionInfluence = clamp(motion * motionSense, 0.0, 1.0);
    lagAmount = lagAmount * (1.0 - motionInfluence * 0.7);
  }
  
  // Temporal blending based on lag
  let blendFactor = lagAmount * bufferLength;
  var delayedColor = mix(currentColor.rgb, historyColor.rgb, blendFactor);
  
  // Feedback accumulation for trail effects
  let feedbackColor = mix(currentColor.rgb, historyColor.rgb, feedbackMix);
  
  // Store updated history (blend current into history)
  let newHistory = mix(historyColor.rgb, currentColor.rgb, 0.1 + (1.0 - lagAmount) * 0.3);
  textureStore(dataTextureA, vec2<i32>(coord), vec4<f32>(newHistory, 1.0));
  
  // Additional echo effect - chromatic time separation
  let chromaLag = lagAmount * 0.02;
  let rDelayed = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(chromaLag, 0.0), 0.0).r;
  let bDelayed = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(chromaLag, 0.0), 0.0).b;
  
  var finalColor = delayedColor;
  
  // Add chromatic time aberration
  finalColor = vec3<f32>(
    mix(finalColor.r, rDelayed, lagAmount * 0.3),
    finalColor.g,
    mix(finalColor.b, bDelayed, lagAmount * 0.3)
  );
  
  // Ghosting effect - show faint echoes
  let ghostIntensity = lagAmount * 0.3;
  let ghost = historyColor.rgb * ghostIntensity;
  finalColor = finalColor + ghost * 0.2;
  
  // Edge glow for motion
  if (motion > 0.1) {
    let glowColor = vec3<f32>(0.3, 0.6, 1.0) * motion * 0.5;
    finalColor = finalColor + glowColor;
  }
  
  // Vignette based on lag intensity
  let lagVignette = 1.0 - lagAmount * 0.2;
  finalColor = finalColor * lagVignette;
  
  // Clamp
  finalColor = clamp(finalColor, vec3<f32>(0.0), vec3<f32>(1.0));
  
  textureStore(writeTexture, vec2<i32>(coord), vec4<f32>(finalColor, 1.0));
  textureStore(writeDepthTexture, vec2<i32>(coord), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
