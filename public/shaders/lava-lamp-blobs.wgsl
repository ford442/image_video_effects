// ═══════════════════════════════════════════════════════════════════
//  Lava Lamp Blobs
//  Category: generative
//  Features: procedural, audio-reactive, mouse-driven, temporal, chromatic,
//            upgraded-rgba, depth-aware, aces-tone-map, oklab-mix,
//            blackbody-temp, subsurface-glow, ign-dither, per-blob-fft,
//            spring-damper-mouse, click-heat-injection
//  Complexity: High
//  Created: 2026-05-31
//  Upgraded: 2026-09-27
//  Ideas: saddle meniscus in the melt window; cooler wax skin outside the blob
//  A packing: raw (blobShape, blobHalo, heat, alpha). ACES on writeTexture only.
//  Kept: 2026-07-26 blackbody core, per-blob FFT, click heat, spring mouse.
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn sat(x: f32) -> f32 { return clamp(x, 0.0, 1.0); }

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}
fn hash22(p: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(hash21(p), hash21(p + vec2<f32>(29.5, 11.3)));
}

fn linear_srgb_to_oklab(c: vec3<f32>) -> vec3<f32> {
  let l = 0.4122214708*c.r + 0.5363325363*c.g + 0.0514459929*c.b;
  let m = 0.2119034982*c.r + 0.6806995451*c.g + 0.1073969566*c.b;
  let s = 0.0883024619*c.r + 0.2817188376*c.g + 0.6299787005*c.b;
  let l_ = pow(l, 1.0/3.0); let m_ = pow(m, 1.0/3.0); let s_ = pow(s, 1.0/3.0);
  return vec3<f32>(0.2104542553*l_+0.7936177850*m_-0.0040720468*s_,
                   1.9779984951*l_-2.4285922050*m_+0.4505937099*s_,
                   0.0259040371*l_+0.7827717662*m_-0.8086757660*s_);
}
fn oklab_to_linear_srgb(c: vec3<f32>) -> vec3<f32> {
  let l_ = c.x+0.3963377774*c.y+0.2158037573*c.z;
  let m_ = c.x-0.1055613458*c.y-0.0638541728*c.z;
  let s_ = c.x-0.0894841775*c.y-1.2914855480*c.z;
  let l = l_*l_*l_; let m = m_*m_*m_; let s = s_*s_*s_;
  return vec3<f32>(4.0767416621*l-3.3077115913*m+0.2309699292*s,
                  -1.2684380046*l+2.6097574011*m-0.3413193965*s,
                  -0.0041960863*l-0.7034186147*m+1.7076147010*s);
}
fn mixOkLab(a: vec3<f32>, b: vec3<f32>, t: f32) -> vec3<f32> {
  return oklab_to_linear_srgb(mix(linear_srgb_to_oklab(a), linear_srgb_to_oklab(b), t));
}

fn blackbodyRGB(T: f32) -> vec3<f32> {
  let t = clamp(T, 1000.0, 40000.0) / 100.0;
  var r = 0.0; var g = 0.0; var b = 0.0;
  if (t <= 66.0) { r = 1.0; }
  else { r = clamp(329.698727446 * pow(t - 60.0, -0.1332047592) / 255.0, 0.0, 1.0); }
  if (t <= 66.0) { g = clamp((99.4708025861 * log(t) - 161.1195681661) / 255.0, 0.0, 1.0); }
  else { g = clamp(288.1221695283 * pow(t - 60.0, -0.0755148492) / 255.0, 0.0, 1.0); }
  if (t >= 66.0) { b = 1.0; }
  else if (t <= 19.0) { b = 0.0; }
  else { b = clamp((138.5177312231 * log(t - 10.0) - 305.0447927307) / 255.0, 0.0, 1.0); }
  return vec3<f32>(r, g, b);
}

fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
  return a + b * cos(6.28318 * (c * t + d));
}

fn hue_preserve_clamp(c: vec3<f32>, max_lum: f32) -> vec3<f32> {
  let l = dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
  let s = min(1.0, max_lum / max(l, 1e-4));
  return c * s;
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x*(a*x+b))/(x*(c*x+d)+e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn ign(p: vec2<f32>) -> f32 {
  return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}

// Metaball field. Each blob owns an FFT voice: bin (i % 8) + 1 pulses its
// size individually, so the lamp breathes per-blob with the spectrum.
// shimmer = mids-driven wobble of the effective blob population.
fn blobField(p: vec2<f32>, time: f32, count: f32, speed: f32, shimmer: f32) -> f32 {
  var field = 0.0;
  let effCount = count * (1.0 + shimmer * 0.3 * sin(time * 2.3));
  for (var i = 0u; i < u32(effCount); i = i + 1u) {
    let fi = f32(i);
    let seed = hash22(vec2<f32>(fi, 11.7));
    let voice = plasmaBuffer[(i % 8u) + 1u].x;
    let phase = fi * 6.28318 / max(effCount, 1.0);
    let bx = sin(phase + time * speed * (0.3 + seed.x * 0.5)) * (0.5 + seed.x * 0.3);
    let by = -0.8 + fract(fi / max(effCount, 1.0) + time * speed * (0.1 + seed.y * 0.2)) * 1.6;
    let d = length(p - vec2<f32>(bx, by));
    let size = (0.12 + seed.y * 0.08) * (1.0 + voice * 0.45);
    field = field + exp(-d * d / (size * size)) * (0.75 + voice * 0.5);
  }
  return field;
}

// Click heat injections: each ripple spawns a temporary blob that rises and
// dissolves with ripple age. Returns field contribution; clickHeat (out via
// ptr not available) folded into the field itself scaled by life.
fn clickField(p: vec2<f32>, time: f32, aspect: f32, riseSpeed: f32, heat: f32) -> vec2<f32> {
  var field = 0.0;
  var hottest = 0.0;
  let nRip = min(u32(u.config.y), 50u);
  for (var ri = 0u; ri < nRip; ri = ri + 1u) {
    let rp = u.ripples[ri];
    let age = time - rp.z;
    if (age > 0.0 && age < 4.0) {
      let life = 1.0 - age / 4.0;
      var cpos = rp.xy * 2.0 - 1.0;
      cpos.x = cpos.x * aspect;
      // The injected blob rises like fresh wax, accelerating with age.
      cpos.y = cpos.y + age * age * 0.08 + age * (0.15 + riseSpeed * 0.4);
      let d = length(p - cpos);
      let sz = 0.07 + 0.06 * life;
      let w = exp(-d * d / (sz * sz)) * life * life;
      field = field + w;
      hottest = max(hottest, life * exp(-d * d / 0.3));
    }
  }
  return vec2<f32>(field * (0.6 + heat * 0.6), hottest);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }

  let uv = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(dims);
  let coord = vec2<i32>(gid.xy);
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // ── Slider wiring (zoom_params.x/y/z/w) ─────────────────────────
  let blobCount = mix(2.0, 10.0, u.zoom_params.x);   // Blob Count: population
  let riseSpeed = mix(0.05, 0.6, u.zoom_params.y);   // Rise Speed: wax velocity
  let melt = mix(0.0, 1.0, u.zoom_params.z);         // Melt: merge threshold
  let heat = mix(0.3, 2.0, u.zoom_params.w);         // Heat: core temperature

  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  var p = uv * 2.0 - 1.0;
  p.x = p.x * aspect;

  // ── Aspect-corrected, spring-dampered mouse attraction ──────────
  // Persistent state: extraBuffer[133]=pos.x [134]=pos.y [135]=vel.x [136]=vel.y
  // Single writer at (0,0). Every pixel reads the stored center.
  let sPos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  if (gid.x == 0u && gid.y == 0u) {
    var springTarget = u.zoom_config.yz * 2.0 - 1.0;
    springTarget.x = springTarget.x * aspect;
    var sVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    let dt = 0.016;
    let stiffness = 42.0;
    let damping = 9.0;
    let force = (springTarget - sPos) * stiffness - sVel * damping;
    sVel = sVel + force * dt;
    let nextPos = sPos + sVel * dt;
    extraBuffer[133] = nextPos.x;
    extraBuffer[134] = nextPos.y;
    extraBuffer[135] = sVel.x;
    extraBuffer[136] = sVel.y;
  }
  p = p + sPos * 0.18;

  // ── Field evaluation ────────────────────────────────────────────
  let blobs = blobField(p, time, blobCount, riseSpeed, mids);
  let click = clickField(p, time, aspect, riseSpeed, heat);
  let totalField = blobs + click.x;

  // Melt widens the merge window: blobs fuse into goopy continents.
  let edge0 = mix(0.5, 0.32, melt);
  let edge1 = mix(1.2, 0.85, melt);
  let blobShape = smoothstep(edge0, edge1, totalField);
  let blobHalo = smoothstep(0.2, 0.8, totalField) * (1.0 - blobShape);
  let blobCenter = smoothstep(1.0, 1.5, totalField);

  // Previous frame is raw fields, not display color.
  let prevField = textureLoad(dataTextureC, coord, 0);
  let e = 0.025;
  let fx = blobField(p + vec2<f32>(e, 0.0), time, blobCount, riseSpeed, mids)
         - blobField(p - vec2<f32>(e, 0.0), time, blobCount, riseSpeed, mids);
  let fy = blobField(p + vec2<f32>(0.0, e), time, blobCount, riseSpeed, mids)
         - blobField(p - vec2<f32>(0.0, e), time, blobCount, riseSpeed, mids);
  let grad = length(vec2<f32>(fx, fy));
  let inMelt = smoothstep(edge0, (edge0 + edge1) * 0.5, totalField)
             * (1.0 - smoothstep((edge0 + edge1) * 0.5, edge1, totalField));
  let meniscus = inMelt * exp(-grad * grad * 6.0) * (0.65 + prevField.r * 0.35);
  let skin = smoothstep(edge0 - 0.12, edge0, totalField) * (1.0 - blobShape);

  // Blackbody temperature: warm core, cool halo, driven by audio + click heat
  let coreTemp = 2000.0 + heat * 3000.0 + bass * 2000.0 + click.y * 2500.0;
  let haloTemp = 6000.0 + mids * 4000.0 + click.y * 1500.0;
  let coreCol = blackbodyRGB(coreTemp) * vec3<f32>(1.3, 1.0, 0.8);
  let haloCol = blackbodyRGB(haloTemp) * vec3<f32>(0.7, 0.9, 1.1);

  // Palette-driven variation for organic color shifts
  let paletteCol = palette(totalField * 2.0 + time * 0.3 + bass,
    vec3<f32>(0.5,0.5,0.5), vec3<f32>(0.5,0.5,0.5),
    vec3<f32>(1.0,1.0,0.5), vec3<f32>(0.0,0.1,0.2));

  // Subsurface scattering glow: light penetrates blob edges
  let sss = exp(-totalField * 2.0) * blobHalo * 0.6;
  // Fresnel rim with treble-driven sparkle: glittering wax edges
  let sparkle = step(0.985 - treble * 0.05, ign(floor(p * 90.0) + vec2<f32>(time * 7.0)));
  let rim = pow(blobHalo, 3.0) * (1.0 + treble * 0.5 + sparkle * treble * 2.0);

  // 3-point lighting: key (warm core) + fill (cool halo) + rim (hot edge)
  var color = vec3<f32>(0.02, 0.02, 0.05);
  color = color + coreCol * blobShape * heat * (1.5 + bass * 0.5);
  color = color + mixOkLab(haloCol, paletteCol, 0.3) * blobHalo * melt * (0.8 + mids * 0.3);
  color = color + vec3<f32>(1.0, 0.85, 0.6) * sss * 0.5;
  color = color + vec3<f32>(1.2, 0.9, 0.7) * rim * 0.8;
  color = color + vec3<f32>(1.0, 0.95, 0.9) * blobCenter * treble * 1.2;
  color = color + vec3<f32>(1.0, 0.72, 0.35) * meniscus * (0.8 + bass);
  let skinTemp = mix(900.0, coreTemp * 0.45, 0.5);
  color = color + blackbodyRGB(skinTemp) * skin * 0.9;
  // Click injections bleed extra ember light where they dissolve
  color = color + blackbodyRGB(2800.0 + click.y * 2000.0) * click.y * click.x * 1.5;

  // Volumetric haze (Beer-Lambert) for depth atmosphere
  let distFromCenter = length(p);
  let haze = exp(-distFromCenter * 1.2);
  color = color * haze + mixOkLab(vec3<f32>(0.02,0.02,0.05), haloCol * 0.08, 0.4) * (1.0 - haze);

  // Tonemap & dither stack
  color = hue_preserve_clamp(color, 4.0);
  color = aces(color);
  let dither = (ign(vec2<f32>(gid.xy)) - 0.5) / 255.0;
  color = color + vec3<f32>(dither);

  // Bloom-weight alpha
  let luma = dot(color, vec3<f32>(0.2126, 0.7152, 0.0722));
  let bloomWeight = pow(max(0.0, luma - 0.5), 2.0) * 3.0;
  let presence = sat(blobShape * 0.9 + blobHalo * 0.5);
  let alpha = sat(0.12 + presence * 0.88);
  let a = max(alpha, bloomWeight * 0.6);
  let depth = sat(0.9 - blobShape * 0.55 - blobHalo * 0.2);

  let outRGB = pow(color, vec3<f32>(1.0/2.2));
  textureStore(writeTexture, coord, vec4<f32>(outRGB * a, a));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 1.0));
  // SIM STATE packing preserved VERBATIM: (blobShape, blobHalo, heat, a)
  textureStore(dataTextureA, coord, vec4<f32>(blobShape, blobHalo, heat, a));
}
