// ----------------------------------------------------------------
// Cybernetic-Mycelium Neural-Web
// Category: generative
// ----------------------------------------------------------------
//  Features: procedural, audio-reactive, mouse-driven, temporal, chromatic,
//            organic, mycelium, neural-network, bioluminescence, particle-trails,
//            upgraded-rgba
// ----------------------------------------------------------------

struct Uniforms {
  config      : vec4<f32>,
  zoom_config : vec4<f32>,
  zoom_params : vec4<f32>,
  ripples     : array<vec4<f32>, 50>,
};

@group(0) @binding(0) var u_sampler                : sampler;
@group(0) @binding(1) var readTexture              : texture_2d<f32>;
@group(0) @binding(2) var writeTexture             : texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u               : Uniforms;
@group(0) @binding(4) var readDepthTexture         : texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler    : sampler;
@group(0) @binding(6) var writeDepthTexture        : texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA             : texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB             : texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC             : texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer : array<f32>;
@group(0) @binding(11) var comparison_sampler      : sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer : array<vec4<f32>>;

const PI : f32 = 3.14159265358979323846;

fn hash2(p: vec2<f32>) -> f32 {
  var q = fract(p * vec2<f32>(0.1031, 0.1030));
  q += dot(q, q + 33.33);
  return fract((q.x + q.y) * q.x);
}

fn hash3(p: vec3<f32>) -> f32 {
  var q = fract(p * 0.1031);
  q += dot(q, q.yzx + 33.33);
  return fract((q.x + q.y) * q.z);
}

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash2(i+vec2<f32>(0,0)), hash2(i+vec2<f32>(1,0)), u.x),
    mix(hash2(i+vec2<f32>(0,1)), hash2(i+vec2<f32>(1,1)), u.x), u.y);
}

fn noise3(p: vec3<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(mix(hash3(i+vec3<f32>(0,0,0)), hash3(i+vec3<f32>(1,0,0)), u.x),
        mix(hash3(i+vec3<f32>(0,1,0)), hash3(i+vec3<f32>(1,1,0)), u.x), u.y),
    mix(mix(hash3(i+vec3<f32>(0,0,1)), hash3(i+vec3<f32>(1,0,1)), u.x),
        mix(hash3(i+vec3<f32>(0,1,1)), hash3(i+vec3<f32>(1,1,1)), u.x), u.y), u.z);
}

fn fbm(p: vec2<f32>) -> f32 {
  var v = 0.0; var a = 0.5; var pp = p;
  for(var i = 0; i < 5; i++) {
    v += a * noise2(pp);
    pp = pp * 2.03 + vec2<f32>(1.7, 3.1);
    a *= 0.5;
  }
  return v;
}

fn rot(a: f32) -> mat2x2<f32> {
  let c = cos(a); let s = sin(a);
  return mat2x2<f32>(c, -s, s, c);
}

fn bass_env(prev: f32, curr: f32, att: f32, rel: f32) -> f32 {
  if(curr > prev) { return mix(prev, curr, att); }
  else { return mix(prev, curr, rel); }
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = vec2<f32>(u.config.z, u.config.w);
  let fragCoord = vec2<f32>(f32(global_id.x), f32(global_id.y));
  if (fragCoord.x >= res.x || fragCoord.y >= res.y) { return; }

  let uv = (fragCoord - 0.5 * res) / res.y;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mid = plasmaBuffer[0].y;

  let growthRate = u.zoom_params.x;
  let pulseIntensity = u.zoom_params.y;
  let decaySpeed = u.zoom_params.z;
  let complexity = u.zoom_params.w;

  // ═══ CHUNK: bass_env smoothing ═══
  let prevBass = extraBuffer[0];
  let bassSmooth = bass_env(prevBass, bass, 0.08, 0.02);
  extraBuffer[0] = bassSmooth;

  // Mouse as nutrient source
  let mouseUV = u.zoom_config.yz;
  let mousePos = (mouseUV - 0.5) * vec2<f32>(res.x / res.y, 1.0) * 2.5;
  let mouseY = 1.0 - mouseUV.y;  // Flip Y
  let mouseWorld = vec3<f32>(mousePos.x, mouseY * 2.0, 0.0);

  // KIFS structural lattice (nutrient hotspots)
  var z = vec3<f32>(uv.x, uv.y, 0.0) * complexity * 3.0;
  var dr = 1.0;
  for(var i = 0; i < 5; i++) {
    z = abs(z);
    if(z.x + z.y < 0.0) { let t = -z.y; z.y = z.x; z.x = t; }
    if(z.x + z.z < 0.0) { let t = -z.z; z.z = z.x; z.x = t; }
    z = z * 2.0 - vec3<f32>(1.0, 1.0, 1.0);
    dr *= 2.0;
  }
  let hotspot = length(z) / abs(dr);

  // Mycelial trail density (simulated via fbm)
  let trailP = uv * 4.0 + time * 0.1 * growthRate;
  let trailDensity = fbm(trailP) * fbm(trailP * 1.5 + vec2<f32>(time * 0.2, -time * 0.15));

  // Mouse attraction
  let toMouse = mouseWorld.xy - uv;
  let mouseDist = length(toMouse);
  let mouseAttraction = exp(-mouseDist * mouseDist * 2.0) * 3.0;

  // Data pulses traveling along high-density trails
  let pulsePhase = fract(time * 0.5 * pulseIntensity + trailDensity * 3.0);
  let pulse = exp(-pow(pulsePhase - 0.5, 2.0) * 50.0) * pulseIntensity;

  // Audio-reactive growth
  let audioGrowth = 1.0 + bassSmooth * 2.0;
  let totalDensity = trailDensity * audioGrowth + mouseAttraction;

  // Decay
  let age = fract(hash2(floor(uv * 20.0)) + time * decaySpeed);
  let alive = smoothstep(0.0, 0.3, age) * smoothstep(1.0, 0.7, age);

  // Color mapping
  // Base threads: bio-mechanical dark purples and metallic greys
  let bioCol = mix(
    vec3<f32>(0.15, 0.05, 0.2),
    vec3<f32>(0.35, 0.35, 0.38),
    trailDensity
  );

  // Data pulses: neon greens and cyans
  let pulseCol = mix(
    vec3<f32>(0.0, 1.0, 0.4),
    vec3<f32>(0.0, 0.8, 1.0),
    sin(time * 2.0 + uv.x * 5.0) * 0.5 + 0.5
  ) * pulse;

  // Bioluminescence at intersections
  let intersection = smoothstep(0.4, 0.6, trailDensity) * smoothstep(0.6, 0.4, trailDensity);
  let bioLum = vec3<f32>(0.2, 1.0, 0.6) * intersection * bassSmooth * 2.0;

  // Mouse hotspot glow
  let mouseGlow = vec3<f32>(0.8, 0.3, 1.0) * mouseAttraction * 0.5;

  // Combine
  var col = bioCol * alive;
  col += pulseCol;
  col += bioLum;
  col += mouseGlow;

  // Organic subsurface scattering simulation
  let sss = fbm(uv * 6.0 + time * 0.05) * 0.1;
  col += vec3<f32>(0.1, 0.05, 0.15) * sss;

  // Audio bloom
  col += vec3<f32>(0.0, 0.2, 0.1) * bassSmooth * bassSmooth * 0.3;

  // Chromatic edge aberration on dense areas
  let ca = totalDensity * 0.02;
  col.r += noise2(uv + vec2<f32>(ca, 0.0)) * ca;
  col.b += noise2(uv - vec2<f32>(ca, 0.0)) * ca;

  // Temporal feedback
  let prevCol = textureLoad(dataTextureC, vec2<i32>(global_id.xy), 0).rgb;
  col = mix(prevCol, col, 0.3);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(col, 1.0));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(0.0, 0.0, 0.0, 0.0));
}
