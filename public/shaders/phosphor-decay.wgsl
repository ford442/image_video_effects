// ═══ Phosphor Decay (Visualist Upgrade) ═══════════════════════════
//  Category: retro-glitch
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba,
//            oklab-mixed, blackbody-graded, ign-dithered
//  Complexity: Medium
//  Upgrades: OkLab phosphor blending, blackbody temperature grading,
//            hue-preserving HDR clamp, IGN dither, premultiplied bloom alpha

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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn to_linear(c: vec3<f32>) -> vec3<f32> { return pow(c, vec3<f32>(2.2)); }
fn to_srgb(c: vec3<f32>) -> vec3<f32> { return pow(c, vec3<f32>(1.0 / 2.2)); }

fn aces_tone_map(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hue_preserve_clamp(c: vec3<f32>, max_lum: f32) -> vec3<f32> {
    let l = dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
    return c * min(1.0, max_lum / max(l, 1e-4));
}

fn linear_srgb_to_oklab(c: vec3<f32>) -> vec3<f32> {
    let l = 0.4122214708*c.r + 0.5363325363*c.g + 0.0514459929*c.b;
    let m = 0.2119034982*c.r + 0.6806995451*c.g + 0.1073969566*c.b;
    let s = 0.0883024619*c.r + 0.2817188376*c.g + 0.6299787005*c.b;
    let l_ = pow(l, 1.0/3.0); let m_ = pow(m, 1.0/3.0); let s_ = pow(s, 1.0/3.0);
    return vec3<f32>(
        0.2104542553*l_+0.7936177850*m_-0.0040720468*s_,
        1.9779984951*l_-2.4285922050*m_+0.4505937099*s_,
        0.0259040371*l_+0.7827717662*m_-0.8086757660*s_);
}

fn oklab_to_linear_srgb(c: vec3<f32>) -> vec3<f32> {
    let l_ = c.x+0.3963377774*c.y+0.2158037573*c.z;
    let m_ = c.x-0.1055613458*c.y-0.0638541728*c.z;
    let s_ = c.x-0.0894841775*c.y-1.2914855480*c.z;
    let l = l_*l_*l_; let m = m_*m_*m_; let s = s_*s_*s_;
    return vec3<f32>(
        4.0767416621*l-3.3077115913*m+0.2309699292*s,
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

fn vignette(uv: vec2<f32>, strength: f32) -> f32 {
    let d = length(uv - vec2<f32>(0.5));
    return pow(max(0.0, 1.0 - d * 2.0), strength);
}

fn chromatic_aberration(uv: vec2<f32>, amount: f32) -> vec3<f32> {
    let offset = (uv - vec2<f32>(0.5)) * amount;
    let r = textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uv - offset, 0.0).b;
    return vec3<f32>(r, g, b);
}

fn ign(p: vec2<f32>) -> f32 {
    return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res   = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv   = vec2<f32>(pixel) / res;
    let time = u.config.x;

    let decayRateParam     = u.zoom_params.x;
    let bloomSpread        = u.zoom_params.y;
    let shadowMaskStrength = u.zoom_params.z;
    let scanBlanking       = u.zoom_params.w;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Per-channel phosphor decay
    let decay = vec3<f32>(
        0.95 - decayRateParam * 0.1,
        0.96 - decayRateParam * 0.1,
        0.98 - decayRateParam * 0.05
    );
    let prev = textureLoad(dataTextureC, pixel, 0);
    var history = to_linear(prev.rgb) * decay;

    // Current input + chromatic aberration
    let inputRGB  = chromatic_aberration(uv, 0.003 + treble * 0.001);
    var inputColor = to_linear(inputRGB);

    // Audio-reactive bloom
    let spread = bloomSpread * 0.02 * (1.0 + bass * 2.0);
    var bloom = vec3<f32>(0.0);
    bloom += to_linear(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(spread, 0.0), 0.0).rgb) * 0.25;
    bloom += to_linear(textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(spread, 0.0), 0.0).rgb) * 0.25;
    bloom += to_linear(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, spread), 0.0).rgb) * 0.25;
    bloom += to_linear(textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(0.0, spread), 0.0).rgb) * 0.25;

    let inputLuma = dot(inputColor, vec3<f32>(0.299, 0.587, 0.114));
    let bloomAdd  = bloom * smoothstep(0.5, 1.0, inputLuma) * bloomSpread * (1.0 + bass * 2.0);
    inputColor += bloomAdd;

    // Merge through OkLab for smooth phosphor trails
    var merged = mixOkLab(history, inputColor, 0.35 + bass * 0.15);
    merged = max(merged, history * 0.85);

    // CRT shadow mask
    let maskX = pixel.x % 3;
    var mask = vec3<f32>(0.6, 0.6, 1.0);
    if (maskX == 0) { mask = vec3<f32>(1.0, 0.6, 0.6); }
    else if (maskX == 1) { mask = vec3<f32>(0.6, 1.0, 0.6); }
    merged = mix(merged, merged * mask, shadowMaskStrength * (1.0 + mids * 0.6) * 0.5);

    // Scan-line blanking
    let scanLine = sin(uv.y * res.y * 0.5) * 0.5 + 0.5;
    merged *= mix(1.0, scanLine, scanBlanking * (1.0 + treble * 0.4) * 0.4);

    // Depth haze via OkLab
    let depth = textureLoad(readDepthTexture, pixel, 0).r;
    let hazeColor = vec3<f32>(0.08, 0.06, 0.04) * 1.5;
    merged = mixOkLab(merged, hazeColor, depth * 0.25);

    // Blackbody temperature grading driven by mids and depth
    let temp = 3200.0 + mids * 3000.0 + depth * 1500.0;
    merged *= blackbodyRGB(temp);

    // CRT vignette
    merged *= vignette(uv, 1.2);

    // HDR clamp, ACES, sRGB
    merged = hue_preserve_clamp(merged, 2.0);
    var finalRGB = aces_tone_map(merged);
    finalRGB = to_srgb(finalRGB);

    // Semantic alpha = bloom weight, IGN dither, premultiplied write
    let luma = dot(finalRGB, vec3<f32>(0.2126, 0.7152, 0.0722));
    let bloomWeight = pow(max(0.0, luma - 0.55), 2.0) * 3.0;
    let alpha = clamp(bloomWeight, 0.0, 1.0);
    let dither = (ign(vec2<f32>(pixel)) - 0.5) / 255.0;
    finalRGB = finalRGB + vec3<f32>(dither);

    textureStore(writeTexture, pixel, vec4<f32>(finalRGB * alpha, alpha));
    textureStore(dataTextureA, pixel, vec4<f32>(finalRGB, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
