// ----------------------------------------------------------------
// Sentient Ferro-Silicate Swarm
// Category: generative
// ----------------------------------------------------------------
//  Features: procedural, audio-reactive, mouse-driven, temporal, chromatic,
//            particle-swarm, SDF-attraction, liquid-chrome, iridescence,
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
    mix(hash2(i + vec2<f32>(0,0)), hash2(i + vec2<f32>(1,0)), u.x),
    mix(hash2(i + vec2<f32>(0,1)), hash2(i + vec2<f32>(1,1)), u.x),
    u.y);
}

fn noise3(p: vec3<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  let n = i.x + i.y * 57.0 + i.z * 113.0;
  return mix(
    mix(mix(hash3(i+vec3<f32>(0,0,0)), hash3(i+vec3<f32>(1,0,0)), u.x),
        mix(hash3(i+vec3<f32>(0,1,0)), hash3(i+vec3<f32>(1,1,0)), u.x), u.y),
    mix(mix(hash3(i+vec3<f32>(0,0,1)), hash3(i+vec3<f32>(1,0,1)), u.x),
        mix(hash3(i+vec3<f32>(0,1,1)), hash3(i+vec3<f32>(1,1,1)), u.x), u.y),
    u.z);
}

fn fbm(p: vec3<f32>) -> f32 {
  var v = 0.0; var a = 0.5; var pp = p;
  for(var i = 0; i < 5; i++) {
    v += a * noise3(pp);
    pp = pp * 2.03 + vec3<f32>(1.7, 3.1, 5.3);
    a *= 0.5;
  }
  return v;
}

fn curlNoise(p: vec3<f32>, time: f32) -> vec3<f32> {
  let eps = 0.01;
  let n1 = noise3(p + vec3<f32>(eps, 0.0, 0.0) + time);
  let n2 = noise3(p - vec3<f32>(eps, 0.0, 0.0) + time);
  let n3 = noise3(p + vec3<f32>(0.0, eps, 0.0) + time);
  let n4 = noise3(p - vec3<f32>(0.0, eps, 0.0) + time);
  let n5 = noise3(p + vec3<f32>(0.0, 0.0, eps) + time);
  let n6 = noise3(p - vec3<f32>(0.0, 0.0, eps) + time);
  return vec3<f32>(
    (n4 - n3) / (2.0 * eps),
    (n1 - n2) / (2.0 * eps),
    (n6 - n5) / (2.0 * eps)
  );
}

fn kIFS(p: vec3<f32>, time: f32) -> f32 {
  var z = p;
  var dr = 1.0;
  for(var i = 0; i < 6; i++) {
    z = abs(z);
    if(z.x + z.y < 0.0) { let t = -z.y; z.y = z.x; z.x = t; }
    if(z.x + z.z < 0.0) { let t = -z.z; z.z = z.x; z.x = t; }
    if(z.y + z.z < 0.0) { let t = -z.z; z.z = z.y; z.y = t; }
    z = z * 2.1 - vec3<f32>(1.1, 1.1, 1.1);
    dr = dr * 2.1;
  }
  return length(z) / abs(dr);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
  let h = max(k - abs(a - b), 0.0) / k;
  return min(a, b) - h * h * k * 0.25;
}

fn rot(a: f32) -> mat2x2<f32> {
  let c = cos(a); let s = sin(a);
  return mat2x2<f32>(c, -s, s, c);
}

fn bass_env(prev: f32, curr: f32, att: f32, rel: f32) -> f32 {
  if(curr > prev) { return mix(prev, curr, att); }
  else { return mix(prev, curr, rel); }
}

// SDF for brutalist target geometry
fn brutalistSDF(p: vec3<f32>, time: f32) -> f32 {
  let pp = p;
  let box = max(abs(pp.x) - 0.8, max(abs(pp.y) - 1.2, abs(pp.z) - 0.8));
  let col1 = length(max(abs(pp - vec3<f32>(0.4, 0.5, 0.0)) - vec3<f32>(0.3, 0.6, 0.3), vec3<f32>(0.0)));
  let col2 = length(max(abs(pp - vec3<f32>(-0.4, -0.3, 0.0)) - vec3<f32>(0.25, 0.4, 0.25), vec3<f32>(0.0)));
  let structure = min(box, min(col1, col2));
  // Add KIFS fractal detail
  let frac = kIFS(pp * 1.5, time) * 0.2;
  return smin(structure, frac, 0.5);
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
  let treble = plasmaBuffer[0].z;

  let cohesion = u.zoom_params.x;
  let rigidity = u.zoom_params.y;
  let shatterForce = u.zoom_params.z;
  let iridescence = u.zoom_params.w;

  // ═══ CHUNK: bass_env smoothing ═══
  let prevBass = extraBuffer[0];
  let bassSmooth = bass_env(prevBass, bass, 0.08, 0.02);
  extraBuffer[0] = bassSmooth;

  // Pseudo-random particle seed based on pixel position
  let seed = hash2(fragCoord * 0.01 + time * 0.1);
  let particleID = f32(global_id.x + global_id.y * 1000u);

  // Particle position (simulated via domain repetition)
  let gridScale = 0.15;
  let gridUV = uv / gridScale;
  let cellId = floor(gridUV);
  let cellFract = fract(gridUV) - 0.5;

  // Random offset per cell
  let rnd = hash2(cellId + time * 0.01);
  let rnd3 = hash3(vec3<f32>(cellId, time * 0.05));

  // Particle position in cell
  var p = vec3<f32>(
    cellFract.x + (rnd - 0.5) * 0.3,
    cellFract.y + (hash2(cellId + 1.0) - 0.5) * 0.3,
    (rnd3 - 0.5) * 0.5
  );

  // Curl noise flow field
  let curl = curlNoise(vec3<f32>(p.xy * 2.0, time * 0.2), time);
  p += curl * 0.01 * (1.0 - rigidity);

  // SDF attraction (swarm seeks brutalist form)
  let sdfD = brutalistSDF(p, time);
  let sdfForce = -normalize(p) * sdfD * rigidity * 0.02;
  p += sdfForce;

  // Audio-reactive shattering
  let shatter = bassSmooth * shatterForce * 2.0;
  p += curlNoise(p * 3.0 + time, time) * shatter;

  // Mouse interaction (magnetic anomaly)
  let mouseUV = u.zoom_config.yz;
  let mousePos = (mouseUV - 0.5) * vec2<f32>(res.x / res.y, 1.0) * 3.0;
  let mouseY = mouseUV.y;  // Flip Y
  let mouse3D = vec3<f32>(mousePos.x, mouseY * 3.0, 0.0);
  let toMouse = mouse3D - p;
  let mouseDist = length(toMouse);
  let mouseForce = normalize(toMouse) * (1.0 / (1.0 + mouseDist * mouseDist)) * cohesion * 0.5;
  p += mouseForce;

  // Calculate particle color based on state
  let vel = length(curl) + shatter * 0.5;
  let density = 1.0 / (1.0 + abs(sdfD) * 2.0);

  // Liquid chrome base
  let n = normalize(p);
  let viewDir = normalize(vec3<f32>(uv, 1.0));
  let halfDir = normalize(n + viewDir);
  let spec = pow(max(dot(n, halfDir), 0.0), 128.0);
  let fresnel = pow(1.0 - abs(dot(n, viewDir)), 2.0);

  // Iridescent oil-spill
  let oilHue = fract(dot(p, vec3<f32>(1.0, 2.3, 3.7)) * 0.3 + time * 0.1) * iridescence;
  let oilCol = vec3<f32>(
    0.5 + 0.5 * cos(oilHue * 6.28 + 0.0),
    0.5 + 0.5 * cos(oilHue * 6.28 + 2.09),
    0.5 + 0.5 * cos(oilHue * 6.28 + 4.18)
  );

  // High velocity = heat (neon orange/cyan)
  let heatCol = mix(
    vec3<f32>(0.0, 0.8, 1.0),
    vec3<f32>(1.0, 0.4, 0.0),
    smoothstep(0.3, 1.0, vel)
  );

  // Combine
  var col = mix(vec3<f32>(0.7, 0.72, 0.75), oilCol, fresnel * iridescence);
  col += spec * vec3<f32>(1.0) * 0.5;
  col = mix(col, heatCol, smoothstep(0.2, 0.8, vel) * bassSmooth);

  // Density-based brightening
  col *= (0.5 + density * 0.5);

  // Audio bloom
  col += vec3<f32>(0.1, 0.15, 0.2) * bassSmooth * bassSmooth;

  // Chromatic aberration at edges
  let ca = vel * 0.02;
  col.r += noise3(p + vec3<f32>(ca, 0.0, 0.0)) * ca;
  col.b += noise3(p + vec3<f32>(-ca, 0.0, 0.0)) * ca;

  // Temporal feedback
  let prevCol = textureLoad(dataTextureC, vec2<i32>(global_id.xy), 0).rgb;
  col = mix(prevCol, col, 0.25);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(col, 1.0));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(0.0, 0.0, 0.0, 0.0));
}
