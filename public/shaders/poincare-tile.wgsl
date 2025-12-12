// Hyperbolic Tiling - Poincaré Disk Geometry
// Projects image onto hyperbolic plane with Möbius transformations

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
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=unused, y=MouseX, z=MouseY, w=unused
  zoom_params: vec4<f32>,  // x=Curvature, y=Symmetry, z=AnimSpeed, w=TileScale
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// Complex number operations
fn cmul(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

fn cdiv(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
  let denom = b.x * b.x + b.y * b.y;
  return vec2<f32>((a.x * b.x + a.y * b.y) / denom, (a.y * b.x - a.x * b.y) / denom);
}

fn cconj(z: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(z.x, -z.y);
}

fn cabs(z: vec2<f32>) -> f32 {
  return length(z);
}

fn cexp(z: vec2<f32>) -> vec2<f32> {
  let r = exp(z.x);
  return vec2<f32>(r * cos(z.y), r * sin(z.y));
}

fn clog(z: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(log(length(z)), atan2(z.y, z.x));
}

// Möbius transformation: (az + b) / (cz + d)
fn mobius(z: vec2<f32>, a: vec2<f32>, b: vec2<f32>, c: vec2<f32>, d: vec2<f32>) -> vec2<f32> {
  let num = cmul(a, z) + b;
  let den = cmul(c, z) + d;
  return cdiv(num, den);
}

// Hyperbolic translation in Poincaré disk
fn hyperbolicTranslate(z: vec2<f32>, t: vec2<f32>) -> vec2<f32> {
  // Möbius transformation for translation
  let num = z + t;
  let den = cmul(cconj(t), z) + vec2<f32>(1.0, 0.0);
  return cdiv(num, den);
}

// Hyperbolic rotation
fn hyperbolicRotate(z: vec2<f32>, angle: f32) -> vec2<f32> {
  let c = cos(angle);
  let s = sin(angle);
  return vec2<f32>(z.x * c - z.y * s, z.x * s + z.y * c);
}

// Distance in Poincaré disk
fn hyperbolicDist(z1: vec2<f32>, z2: vec2<f32>) -> f32 {
  let delta = cdiv(z1 - z2, vec2<f32>(1.0, 0.0) - cmul(cconj(z2), z1));
  let d = length(delta);
  return 2.0 * atanh(d);
}

fn atanh(x: f32) -> f32 {
  return 0.5 * log((1.0 + x) / (1.0 - x));
}

// Regular polygon tiling parameters
fn getPolyParams(symmetry: f32) -> vec3<f32> {
  // p-gon, q at each vertex
  let p = floor(symmetry * 4.0 + 3.0); // 3 to 7
  let q = floor(symmetry * 2.0 + 3.0); // 3 to 5
  let angle = PI / p;
  return vec3<f32>(p, q, angle);
}

// Map point to fundamental domain
fn toFundamentalDomain(z: vec2<f32>, p: f32, q: f32) -> vec2<f32> {
  var w = z;
  let maxIter = 50;
  
  for (var i = 0; i < maxIter; i = i + 1) {
    // Reflect across edges of hyperbolic polygon
    let angle = atan2(w.y, w.x);
    let sector = floor(angle / (TAU / p) + 0.5);
    let sectorAngle = sector * TAU / p;
    
    // Rotate to first sector
    let c = cos(-sectorAngle);
    let s = sin(-sectorAngle);
    w = vec2<f32>(w.x * c - w.y * s, w.x * s + w.y * c);
    
    // Check if in fundamental domain
    if (w.y >= 0.0 && atan2(w.y, w.x) < PI / p) {
      break;
    }
    
    // Reflect if needed
    if (w.y < 0.0) {
      w.y = -w.y;
    }
  }
  
  return w;
}

// HSV to RGB
fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
  let c = v * s;
  let x = c * (1.0 - abs((h * 6.0) % 2.0 - 1.0));
  let m = v - c;
  
  var rgb: vec3<f32>;
  let hi = i32(floor(h * 6.0)) % 6;
  if (hi == 0) { rgb = vec3<f32>(c, x, 0.0); }
  else if (hi == 1) { rgb = vec3<f32>(x, c, 0.0); }
  else if (hi == 2) { rgb = vec3<f32>(0.0, c, x); }
  else if (hi == 3) { rgb = vec3<f32>(0.0, x, c); }
  else if (hi == 4) { rgb = vec3<f32>(x, 0.0, c); }
  else { rgb = vec3<f32>(c, 0.0, x); }
  
  return rgb + vec3<f32>(m);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w));
  let coord = gid.xy;
  if (coord.x >= size.x || coord.y >= size.y) { return; }
  
  let uv = vec2<f32>(f32(coord.x), f32(coord.y)) / vec2<f32>(f32(size.x), f32(size.y));
  let time = u.config.x;
  
  // Parameters
  let curvature = mix(0.3, 0.95, u.zoom_params.x);
  let symmetry = u.zoom_params.y;
  let animSpeed = mix(0.1, 1.0, u.zoom_params.z);
  let tileScale = mix(0.5, 2.0, u.zoom_params.w);
  
  // Map to centered coordinates (-1 to 1)
  let aspect = u.config.z / u.config.w;
  var z = (uv - vec2<f32>(0.5)) * 2.0;
  z.x = z.x * aspect;
  
  // Scale to disk
  z = z * curvature;
  
  // Check if inside disk
  let r = length(z);
  
  if (r >= 1.0) {
    // Outside disk - show gradient background
    let edgeColor = vec3<f32>(0.05, 0.05, 0.1);
    textureStore(writeTexture, vec2<i32>(coord), vec4<f32>(edgeColor, 1.0));
    textureStore(writeDepthTexture, vec2<i32>(coord), vec4<f32>(0.0, 0.0, 0.0, 0.0));
    return;
  }
  
  // Mouse interaction - use as center of transformation
  let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
  let mouseZ = (mouse - vec2<f32>(0.5)) * 2.0 * curvature * 0.5;
  
  // Animated translation
  let animT = vec2<f32>(
    sin(time * animSpeed * 0.3) * 0.3,
    cos(time * animSpeed * 0.4) * 0.3
  );
  
  // Apply hyperbolic transformations
  var w = z;
  
  // Translate by mouse position
  if (length(mouseZ) < 0.9) {
    w = hyperbolicTranslate(w, mouseZ * 0.5);
  }
  
  // Animated rotation
  w = hyperbolicRotate(w, time * animSpeed * 0.5);
  
  // Apply translation animation
  w = hyperbolicTranslate(w, animT * 0.3);
  
  // Get polygon parameters
  let polyParams = getPolyParams(symmetry);
  let p = polyParams.x;
  let q = polyParams.y;
  
  // Map to fundamental domain (tiling)
  var tiledZ = w;
  var tileIndex = 0.0;
  
  // Simple angular tiling
  let angle = atan2(tiledZ.y, tiledZ.x);
  let sector = floor(angle / (TAU / p) + 0.5);
  tileIndex = sector;
  
  // Reflect to canonical sector
  let sectorAngle = sector * TAU / p;
  let c = cos(-sectorAngle);
  let s = sin(-sectorAngle);
  tiledZ = vec2<f32>(tiledZ.x * c - tiledZ.y * s, tiledZ.x * s + tiledZ.y * c);
  
  // Radial scaling for tile pattern
  let hypR = length(tiledZ);
  let logR = log(hypR + 0.001);
  let tiledR = fract(logR * tileScale + time * animSpeed * 0.2);
  
  // Map to texture UV
  var texUV = vec2<f32>(
    tiledR * cos(atan2(tiledZ.y, tiledZ.x) + tileIndex * 0.5),
    tiledR * sin(atan2(tiledZ.y, tiledZ.x) + tileIndex * 0.5)
  ) * 0.5 + vec2<f32>(0.5);
  
  // Alternative: direct mapping with scaling
  texUV = fract(w * tileScale * 0.5 + vec2<f32>(0.5));
  
  // Ripple effects in hyperbolic space
  for (var i = 0; i < 50; i = i + 1) {
    let ripple = u.ripples[i];
    if (ripple.z > 0.0) {
      let rippleAge = time - ripple.z;
      if (rippleAge > 0.0 && rippleAge < 3.0) {
        let rippleZ = (ripple.xy - vec2<f32>(0.5)) * 2.0 * curvature;
        if (length(rippleZ) < 0.9) {
          let dist = hyperbolicDist(w, rippleZ);
          let wave = sin(dist * 5.0 - rippleAge * 3.0) * 0.02;
          let fade = 1.0 - rippleAge / 3.0;
          texUV = texUV + vec2<f32>(wave * fade);
        }
      }
    }
  }
  
  // Sample source texture
  let sourceColor = textureSampleLevel(readTexture, u_sampler, clamp(texUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, clamp(texUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  
  // Add tile boundary visualization
  let boundaryDist = min(abs(tiledZ.y), abs(tiledZ.x * tan(PI / p) - abs(tiledZ.y)));
  let boundary = smoothstep(0.01, 0.02, boundaryDist);
  
  // Hyperbolic shading - darken towards edge
  let edgeDarken = 1.0 - pow(r, 4.0);
  
  // Tile coloring based on sector
  let tileHue = fract(tileIndex / p + time * 0.1);
  let tileColor = hsv2rgb(tileHue, 0.3, 0.8);
  
  // Combine
  var finalColor = sourceColor.rgb * boundary * edgeDarken;
  finalColor = mix(finalColor, tileColor * edgeDarken, 0.1);
  
  // Add subtle glow at center
  let centerGlow = exp(-r * 3.0) * 0.2;
  finalColor = finalColor + vec3<f32>(centerGlow);
  
  textureStore(writeTexture, vec2<i32>(coord), vec4<f32>(finalColor, 1.0));
  textureStore(writeDepthTexture, vec2<i32>(coord), vec4<f32>(depth * edgeDarken, 0.0, 0.0, 0.0));
}
