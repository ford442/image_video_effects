// ═══════════════════════════════════════════════════════════════
//  Charcoal Rub - Physical Media Simulation with Alpha
//  Category: artistic
//  Features: charcoal density → alpha, paper texture grain
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

// Simple hash for noise
fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn noise(x: vec2<f32>) -> f32 {
    var i = floor(x);
    let f = fract(x);
    var a = hash12(i);
    let b = hash12(i + vec2<f32>(1.0, 0.0));
    let c = hash12(i + vec2<f32>(0.0, 1.0));
    let d = hash12(i + vec2<f32>(1.0, 1.0));
    let u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

fn fbm(p: vec2<f32>) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var shift = vec2<f32>(100.0);
    var rot = mat2x2<f32>(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
    var x = p;
    for (var i = 0; i < 5; i++) {
        v = v + a * noise(x);
        x = rot * x * 2.0 + shift;
        a = a * 0.5;
    }
    return v;
}

// Paper grain texture
fn paperGrain(uv: vec2<f32>, scale: f32) -> f32 {
    let grain = fbm(uv * scale);
    return 0.85 + 0.15 * grain;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  var uv = vec2<f32>(global_id.xy) / resolution;

  // Params
  let hardness = mix(0.1, 0.9, u.zoom_params.x);
  let textureScale = mix(10.0, 100.0, u.zoom_params.y);
  let revealRate = mix(0.01, 0.2, u.zoom_params.z);
  let fadeSpeed = mix(0.0, 0.05, u.zoom_params.w);

  var mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;

  // Aspect ratio correction for mouse distance
  let aspect = resolution.x / resolution.y;
  let mouse_aspect = vec2<f32>(mouse.x * aspect, mouse.y);
  let uv_aspect = vec2<f32>(uv.x * aspect, uv.y);

  let dist = distance(uv_aspect, mouse_aspect);

  // Read previous state (reveal mask is in R channel)
  var state = textureLoad(dataTextureC, vec2<i32>(global_id.xy), 0).r;

  // Apply fading
  state = max(0.0, state - fadeSpeed);

  // Apply rubbing
  if (mouseDown > 0.5) {
      let brushRadius = 0.1;
      let brushSoftness = 0.5;
      let brushVal = 1.0 - smoothstep(brushRadius * (1.0 - brushSoftness), brushRadius, dist);

      // Add noise to brush for "rubbing" feel
      let brushNoise = noise(uv * textureScale + u.config.x * 10.0);

      state = min(1.0, state + brushVal * revealRate * (0.5 + 0.5 * brushNoise));
  }

  // Store state
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(state, 0.0, 0.0, 1.0));

  // CHARCOAL PHYSICAL MEDIA ALPHA CALCULATION
  
  // Paper grain affects how charcoal sits on surface
  let paperGrainVal = paperGrain(uv, textureScale * 0.1);
  
  // Charcoal density varies with reveal state and paper texture
  // Charcoal fills valleys in paper first (darker), sits on peaks (lighter)
  let charcoal_density = state * (0.5 + 0.5 * paperGrainVal);
  
  // CHARCOAL THICKNESS → ALPHA MAPPING
  // - Heavy rub = more charcoal particles = higher opacity (0.8-0.95)
  // - Light rub = scattered particles = medium opacity (0.4-0.7)
  // - Paper only = transparent (0.0)
  
  // Base alpha from charcoal density
  var charcoal_alpha = smoothstep(0.0, 0.3, charcoal_density);
  charcoal_alpha = mix(0.0, 0.9, charcoal_alpha * charcoal_alpha);
  
  // Paper texture creates voids in charcoal layer (grain shows through)
  // Peaks in paper = less charcoal contact = more transparency
  let grain_influence = smoothstep(0.3, 0.7, paperGrainVal);
  charcoal_alpha *= mix(0.7, 1.0, grain_influence);
  
  // Edge softness - charcoal particles scatter at edges
  let edge_softness = smoothstep(0.0, 0.4, state) * (1.0 - smoothstep(0.6, 1.0, state));
  charcoal_alpha *= 0.7 + 0.3 * edge_softness;
  
  // Render
  // 1. Generate paper texture
  let paperNoise = fbm(uv * textureScale);
  let paperBaseColor = vec3<f32>(0.95, 0.94, 0.92) * (0.85 + 0.15 * paperNoise);

  // 2. Read actual image
  let imgColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

  // 3. Charcoal effect: Image becomes grayscale and high contrast
  let luma = dot(imgColor, vec3<f32>(0.299, 0.587, 0.114));
  let charcoalColor = vec3<f32>(0.08, 0.07, 0.06) * (0.5 + 0.5 * paperGrainVal); // Warm black
  
  // Charcoal is darker where density is higher, with paper texture modulation
  let charcoal_shade = mix(vec3<f32>(0.25), charcoalColor, charcoal_density);
  
  // Modulate reveal by paper texture for grainy charcoal look
  let revealMask = smoothstep(1.0 - hardness, 1.0, state * paperGrainVal);
  
  // Final color with charcoal media properties
  var final_rgb = mix(paperBaseColor, charcoal_shade, revealMask);
  
  // Add subtle charcoal dust scattering (very low alpha areas)
  let dust_scatter = smoothstep(0.0, 0.15, state) * (1.0 - revealMask) * 0.3;
  let dust_color = vec3<f32>(0.15, 0.14, 0.12) * paperGrainVal;
  final_rgb = mix(final_rgb, dust_color, dust_scatter);
  
  // Alpha modulation by paper grain (paper shows through in grain valleys)
  let grain_alpha_mod = mix(0.85, 1.0, grain_influence);
  charcoal_alpha *= grain_alpha_mod;
  
  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(final_rgb, charcoal_alpha));
  
  // Store charcoal thickness in depth
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(charcoal_density, 0.0, 0.0, charcoal_alpha));
}
