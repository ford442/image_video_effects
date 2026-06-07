// tornado-vortex.wgsl — Visualist upgrade
// Rankine vortex with OkLab mixing, blackbody lightning, volumetric fog

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

fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

fn hash31(p: vec3<f32>) -> f32 {
  let h = dot(p, vec3<f32>(127.1, 311.7, 74.7));
  return fract(sin(h) * 43758.5453123);
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let mouse = u.zoom_config.yz;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  let intensity = u.zoom_params.x;
  let spinSpeed = u.zoom_params.y * 5.0;
  let debrisAmt = u.zoom_params.z;
  let lightningAmt = u.zoom_params.w;

  let aspect = res.x / res.y;
  let p = (uv - 0.5) * vec2<f32>(aspect, 1.0);
  let dist = length(p);
  let angle = atan2(p.y, p.x);

  // Rankine vortex
  let coreRadius = 0.04 * (1.0 + mids * 0.5);
  let circulation = 0.15 * intensity * (1.0 + bass * 0.4);
  let vTheta = select(circulation / (6.28318530718 * dist), circulation * dist / (6.28318530718 * coreRadius * coreRadius), dist > coreRadius);
  let vRadial = -0.02 * intensity * smoothstep(0.3, 0.0, dist);
  let vVertical = 0.1 * intensity * smoothstep(-0.3, 0.4, uv.y) * smoothstep(0.0, 0.1, dist);

  // Volumetric fog density (Beer-Lambert)
  let fogDensity = exp(-dist * 3.0) * 0.15 * intensity;

  var color = vec3<f32>(0.02, 0.03, 0.06);
  var debrisDensity = 0.0;
  var condensation = 0.0;

  // Funnel condensation
  let funnelWidth = coreRadius + (uv.y + 0.5) * 0.22 * (1.0 + mids * 0.4);
  let funnelDist = abs(dist - funnelWidth * (0.55 + sin(uv.y * 12.0 + time * 0.8) * 0.08 * intensity));
  condensation = smoothstep(0.045 * intensity, 0.0, funnelDist) * smoothstep(-0.5, 0.5, uv.y);
  let sss = condensation * condensation * vec3<f32>(0.35, 0.42, 0.48) * 0.6;

  // Spiral streaks
  let spiralPhase = angle + vTheta * time * spinSpeed * 40.0 + uv.y * 18.0;
  let spiral = sin(spiralPhase) * 0.5 + 0.5;
  let spiralMask = condensation * spiral * (0.4 + mids * 0.4);

  // Debris advection
  let debrisCount = 24;
  for (var di = 0; di < debrisCount; di = di + 1) {
    let df = f32(di);
    let seed = hash21(vec2<f32>(df, 0.0));
    let dh = fract(df / f32(debrisCount) + time * 0.08 * (1.0 + bass) + seed * 0.3);
    let dAngle = df * 2.39996 + dh * 8.0 + time * spinSpeed * 0.25 + vTheta * 10.0;
    let dRadius = 0.015 + dh * funnelWidth * 1.1;
    let dPos = vec2<f32>(cos(dAngle), sin(dAngle)) * dRadius;
    let dd = length(p - dPos);
    let dSize = 0.0025 * (1.0 + debrisAmt) * (1.0 + depth * 0.5);
    let particle = smoothstep(dSize, 0.0, dd);
    let sizeFade = 1.0 - smoothstep(0.0, 0.35, dh);
    debrisDensity = debrisDensity + particle * sizeFade;
    color = color + vec3<f32>(0.55, 0.50, 0.45) * particle * debrisAmt * sizeFade;
  }

  // Mouse probe
  let mouseWorld = (mouse - 0.5) * vec2<f32>(aspect, 1.0);
  let mouseDist = length(p - mouseWorld);
  let fling = smoothstep(0.12, 0.0, mouseDist) * vTheta * 3.0 * intensity;
  color = color + vec3<f32>(0.7, 0.65, 0.55) * fling;

  // Lightning with blackbody temperature
  let flashTime = floor(time * (6.0 + treble * 8.0));
  let flash = hash31(vec3<f32>(flashTime, 0.0, 0.0));
  var lightning = step(1.0 - lightningAmt * 0.12 - treble * 0.08, flash) * smoothstep(0.35, 0.0, dist);
  let lightningBranch = sin(angle * 9.0 + flashTime * 3.7) * 0.5 + 0.5;
  lightning = lightning * (0.4 + lightningBranch * 0.6);
  let lightningTemp = blackbodyRGB(6500.0 + treble * 8000.0);
  color += lightningTemp * lightning * (1.5 + treble * 2.0);

  // Ground dust
  let dust = hash21(uv * 55.0 + time * 0.4) * smoothstep(0.0, -0.25, uv.y) * 0.25 * intensity;
  color += vec3<f32>(0.38, 0.33, 0.28) * dust;

  // Build final color with OkLab mixing for funnel
  let funnelBase = mixOkLab(vec3<f32>(0.12, 0.14, 0.16), vec3<f32>(0.35, 0.40, 0.45), spiralMask);
  color = mixOkLab(color, funnelBase, condensation * 0.6);
  color += sss;

  // HDR bloom on lightning
  color += lightningTemp * lightning * lightning * 0.6;

  // Fog attenuation
  color = mix(color, vec3<f32>(0.04, 0.05, 0.08) * blackbodyRGB(3500.0), fogDensity);

  // Tonemap & Dither Stack
  color = hue_preserve_clamp(color, 8.0);
  color = aces(color * 1.5);
  let dither = (ign(vec2<f32>(global_id.xy)) - 0.5) / 255.0;
  color += vec3<f32>(dither);

  // Depth fade
  let depthFade = 1.0 - depth * 0.2;
  color *= depthFade;

  // Bloom-weight alpha
  let luma = dot(color, vec3<f32>(0.2126, 0.7152, 0.0722));
  let bloomWeight = pow(max(0.0, luma - 0.45), 2.0) * 2.5 + lightning * 0.3 + condensation * 0.15;
  let a = clamp(bloomWeight, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color * a, a));
  textureStore(dataTextureA, global_id.xy, vec4<f32>(color, a));
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(condensation * 0.5 + debrisDensity * 0.2, 0.0, 0.0, 0.0));
}
