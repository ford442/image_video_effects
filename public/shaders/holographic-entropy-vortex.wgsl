// ═══════════════════════════════════════════════════════════════════
//  Holographic Entropy Vortex — Visualist Enhanced Edition
//  Category: generative
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=VortexSpeed, y=EntropyScale, z=HolographicIntensity, w=AtmosphereDensity
  ripples: array<vec4<f32>, 50>
};

// ── Color Science ─────────────────────────────────────────────────
fn srgbToLinear(c: vec3<f32>) -> vec3<f32> { return pow(c, vec3<f32>(2.2)); }
fn linearToSrgb(c: vec3<f32>) -> vec3<f32> { return pow(c, vec3<f32>(1.0 / 2.2)); }
fn linearToOkLab(c: vec3<f32>) -> vec3<f32> {
  let lms = mat3x3<f32>(
    0.8189330101, 0.3618667424, -0.1288597137,
    0.0329845436, 0.9293118715, 0.0361456387,
    0.0482003018, 0.2643662691, 0.6338517070
  ) * c;
  let lms_ = sign(lms) * pow(abs(lms), vec3<f32>(1.0 / 3.0));
  return mat3x3<f32>(
    0.2104542553, 0.7936177850, -0.0040720468,
    1.9779984951, -2.4285922050, 0.4505937099,
    0.0259040371, 0.7827717662, -0.8086757660
  ) * lms_;
}
fn okLabToLinear(c: vec3<f32>) -> vec3<f32> {
  let lms_ = mat3x3<f32>(
    1.0, 0.3963377774, 0.2158037573,
    1.0, -0.1055613458, -0.0638541728,
    1.0, -0.0894841775, -1.2914855480
  ) * c;
  let lms = lms_ * lms_ * lms_;
  return mat3x3<f32>(
    4.0767416621, -3.3077115913, 0.2309699292,
    -1.2684380046, 2.6097574011, -0.3413193965,
    -0.0041960863, -0.7034186147, 1.7076147010
  ) * lms;
}
fn okLabMix(a: vec3<f32>, b: vec3<f32>, t: f32) -> vec3<f32> {
  let la = linearToOkLab(srgbToLinear(a));
  let lb = linearToOkLab(srgbToLinear(b));
  return linearToSrgb(okLabToLinear(mix(la, lb, t)));
}
fn aces(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return (x * (a * x + b)) / (x * (c * x + d) + e);
}
fn huePreserveClamp(c: vec3<f32>) -> vec3<f32> {
  let maxc = max(max(c.r, c.g), c.b);
  if (maxc > 1.0) { return c / maxc; }
  return c;
}

fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
  return a + b * cos(6.28318 * (c * t + d));
}

// ── Noise & Geometry ──────────────────────────────────────────────
fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}
fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u2 = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u2.x),
    mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u2.x),
    u2.y
  );
}
fn fbm(p: vec2<f32>) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var f = p;
  for (var i = 0; i < 4; i = i + 1) {
    v = v + a * noise2(f);
    f = f * 2.1 + vec2<f32>(7.13, 3.71);
    a = a * 0.5;
  }
  return v;
}

fn rayleighScattering(cosTheta: f32) -> vec3<f32> {
  let phase = 0.75 * (1.0 + cosTheta * cosTheta);
  return vec3<f32>(0.35, 0.55, 1.0) * phase;
}
fn mieScattering(cosTheta: f32, g: f32) -> f32 {
  let g2 = g * g;
  return (1.0 - g2) / pow(1.0 + g2 - 2.0 * g * cosTheta, 1.5);
}
fn iridescent(dist: f32, freq: f32, hueOffset: f32, fresnel: f32) -> vec3<f32> {
  let phase = dist * freq + hueOffset;
  return vec3<f32>(
    0.5 + 0.5 * sin(phase),
    0.5 + 0.5 * sin(phase + 2.094),
    0.5 + 0.5 * sin(phase + 4.188)
  ) * fresnel;
}
fn caustics(p: vec2<f32>, t: f32) -> f32 {
  let f1 = sin(p.x * 8.0 + t * 1.2) * cos(p.y * 7.0 - t * 0.9);
  let f2 = sin(p.x * 13.0 - t * 0.7) * cos(p.y * 11.0 + t * 1.1);
  return 0.5 + 0.5 * sin(fbm(p + t * 0.05) * 8.0 + t) * (f1 + f2) * 0.5;
}
fn ignDither(p: vec2<f32>, t: f32) -> f32 {
  let fp = fract(p + t * 0.07);
  return fract(52.9829189 * fract(0.06711056 * fp.x + 0.00583715 * fp.y));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = u.config.zw;
  if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }
  
  if (gid.x == 0u && gid.y == 0u) {
    // Persistent state strictly in extraBuffer[133..138] (single-writer)
    let targetX = u.zoom_config.y;
    let targetY = u.zoom_config.z;
    let currX = extraBuffer[133];
    let currY = extraBuffer[134];
    let velX = extraBuffer[135];
    let velY = extraBuffer[136];
    
    // bounded spring
    let springForceX = (targetX - currX) * 0.05;
    let springForceY = (targetY - currY) * 0.05;
    let newVelX = clamp((velX + springForceX) * 0.85, -0.1, 0.1);
    let newVelY = clamp((velY + springForceY) * 0.85, -0.1, 0.1);
    extraBuffer[133] = clamp(currX + newVelX, 0.0, 1.0);
    extraBuffer[134] = clamp(currY + newVelY, 0.0, 1.0);
    extraBuffer[135] = newVelX;
    extraBuffer[136] = newVelY;
    
    // capped click fronts
    let clicks = u.config.y;
    var front = extraBuffer[138];
    if (extraBuffer[137] != clicks) {
       extraBuffer[137] = clicks;
       front = 0.0;
    } else {
       front = min(front + 0.015, 2.0); // capped
    }
    extraBuffer[138] = front;
  }
  workgroupBarrier();

  let uv = vec2<f32>(gid.xy) / dims;
  let t = u.config.x;
  
  let springMouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  let clickFront = extraBuffer[138];
  
  // Truthful three-band audio + bins
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Exact textureLoad from dataTextureC
  let pastC = textureLoad(dataTextureC, vec2<i32>(gid.xy), 0);

  // Params matching original exactly
  let vortexSpeed = mix(0.3, 2.0, u.zoom_params.x);
  let entropyScale = mix(0.5, 3.0, u.zoom_params.y);
  let holoIntensity = mix(0.2, 1.0, u.zoom_params.z);
  let atmoDensity = mix(0.1, 1.0, u.zoom_params.w);

  let centered = uv - 0.5;
  let r = length(centered);
  
  // Continuous geometry & held-pointer response
  let distToMouse = length(uv - springMouse);
  let interact = exp(-distToMouse * 10.0) * u.zoom_config.w; // Held-pointer
  
  let angle = atan2(centered.y, centered.x) + t * (0.6 + r * 3.0) * vortexSpeed * (1.0 + bass * 0.4) - interact;
  let vortexUV = vec2<f32>(cos(angle), sin(angle)) * r + 0.5;

  let n1 = fbm(vortexUV * 4.0 * entropyScale + t * 0.5);
  let entropy = (n1 + interact * 0.5) * (0.5 + mids * 0.5);

  let paletteT = entropy * 2.0 + t * 0.1 + bass * 1.0;
  let paletteA = palette(paletteT,
    vec3<f32>(0.5, 0.5, 0.5),
    vec3<f32>(0.5, 0.5, 0.5),
    vec3<f32>(1.0, 1.0, 1.0),
    vec3<f32>(0.00, 0.33, 0.67)
  );
  let paletteB = palette(paletteT + 0.3 + mids,
    vec3<f32>(0.5, 0.5, 0.5),
    vec3<f32>(0.5 + treble * 0.3, 0.5, 0.5 + bass * 0.3),
    vec3<f32>(0.8, 1.0, 0.9),
    vec3<f32>(0.15, 0.40, 0.65)
  );
  let entropyColor = okLabMix(paletteA, paletteB, 0.5 + sin(t * 0.5) * 0.3);

  let audioTint = plasmaBuffer[0].xyz;
  let baseColor = vec3<f32>(0.4, 0.6, 1.0);
  let tint = mix(baseColor, audioTint, 0.55);

  var rgb = entropy * okLabMix(tint, entropyColor, 0.6);
  
  // Click ripples
  let rippleDist = abs(distToMouse - clickFront * 0.5);
  let ripple = smoothstep(0.05, 0.0, rippleDist) * (2.0 - clickFront);
  rgb = rgb + vec3<f32>(1.0, 0.9, 0.8) * ripple;
  
  // Optical/Prismatic feel (holographic)
  let fresnel = pow(1.0 - r * 1.2, 3.0) * holoIntensity * (0.5 + treble * 0.5);
  let iridColor = iridescent(r, 40.0 + bass * 20.0, t * 2.0, fresnel);
  rgb = rgb + iridColor * entropy * 0.8;
  
  rgb = mix(rgb, pastC.rgb, 0.1); // feedback from C
  
  // Depth
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  rgb = mix(rgb, rgb * (0.6 + depth * 0.8), 0.25);
  
  // HDR workflow & ACES tone map
  rgb = rgb * (1.0 + treble * 0.2);
  rgb = huePreserveClamp(rgb);
  rgb = aces(rgb);
  
  // Semantic alpha
  let alpha = clamp(entropy + ripple + interact, 0.1, 1.0);
  
  let finalColor = vec4<f32>(rgb, alpha);

  // Write final display RGBA ONLY to dataTextureA (and writeTexture)
  textureStore(writeTexture, gid.xy, finalColor);
  textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, gid.xy, finalColor);
}
