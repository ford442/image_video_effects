// Phosphor Decay — Composer batch cyber/digital/glitch cohort 3
// Per-channel linear-feedback decay, OkLab trail blending, blackbody grading,
// spring cursor, held static-charge, capped click blooms, row-voice FFT bins.

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

fn box_bloom(uv: vec2<f32>, spread: f32) -> vec3<f32> {
    let off = vec2<f32>(spread, 0.0);
    var b = vec3<f32>(0.0);
    b += to_linear(textureSampleLevel(readTexture, u_sampler, uv + off, 0.0).rgb);
    b += to_linear(textureSampleLevel(readTexture, u_sampler, uv - off, 0.0).rgb);
    b += to_linear(textureSampleLevel(readTexture, u_sampler, uv + off.yx, 0.0).rgb);
    b += to_linear(textureSampleLevel(readTexture, u_sampler, uv - off.yx, 0.0).rgb);
    return b * 0.25;
}

fn ign(p: vec2<f32>) -> f32 {
    return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}

// Branchless RGB shadow mask: red column, green column, otherwise blue-ish.
fn shadow_mask(pixel_x: i32) -> vec3<f32> {
    let mx = pixel_x % 3;
    let red  = vec3<f32>(1.0, 0.6, 0.6);
    let green = vec3<f32>(0.6, 1.0, 0.6);
    let blue  = vec3<f32>(0.6, 0.6, 1.0);
    var mask = mix(blue, red, f32(mx == 0));
    mask = mix(mask, green, f32(mx == 1));
    return mask;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res   = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv   = vec2<f32>(pixel) / res;
    let time = u.config.x;
    let aspect = res.x / max(res.y, 1.0);
    let held = u.zoom_config.w > 0.5;
    let mouse = u.zoom_config.yz;

    let decayRateParam     = u.zoom_params.x;
    let bloomSpread        = u.zoom_params.y;
    let shadowMaskStrength = u.zoom_params.z;
    let scanBlanking       = u.zoom_params.w;

    let bass   = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids   = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
    let rowVoice = clamp(plasmaBuffer[(u32(pixel.y) % 8u) + 1u].x, 0.0, 1.0);

    var smoothMouse = mouse;
    let hasSpring = arrayLength(&extraBuffer) > 138u;
    if (hasSpring && extraBuffer[138] > 0.5) {
        smoothMouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    }
    if (global_id.x == 0u && global_id.y == 0u && hasSpring) {
        var springPos = smoothMouse;
        var springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
        if (extraBuffer[138] <= 0.5) {
            springPos = mouse;
            springVel = vec2<f32>(0.0);
        } else {
            let dt = clamp(time - extraBuffer[137], 0.001, 0.05);
            let omega = 11.0;
            let accel = (mouse - springPos) * (omega * omega) - springVel * (2.0 * omega);
            springVel += accel * dt;
            springPos += springVel * dt;
        }
        extraBuffer[133] = springPos.x;
        extraBuffer[134] = springPos.y;
        extraBuffer[135] = springVel.x;
        extraBuffer[136] = springVel.y;
        extraBuffer[137] = time;
        extraBuffer[138] = 1.0;
        smoothMouse = springPos;
    }

    // ---- PASS 1: temporal accumulation (cached as linear radiance) ----
    // dataTextureC is the previous frame's copy of dataTextureA.
    let prev = textureLoad(dataTextureC, pixel, 0);

    // Per-channel phosphor decay on linear feedback state.
    let decay = vec3<f32>(
        0.95 - decayRateParam * 0.1,
        0.96 - decayRateParam * 0.1,
        0.98 - decayRateParam * 0.05
    );
    var history = prev.rgb * decay;

    // Current input with audio-reactive chromatic aberration.
    let inputRGB  = chromatic_aberration(uv, 0.003 + treble * 0.001);
    var inputColor = to_linear(inputRGB);

    // Audio-reactive 4-tap box bloom, gated by input luma.
    let spread = bloomSpread * 0.02 * (1.0 + bass * 2.0);
    let bloom  = box_bloom(uv, spread);
    let inputLuma = dot(inputColor, vec3<f32>(0.299, 0.587, 0.114));
    let bloomAdd  = bloom * smoothstep(0.5, 1.0, inputLuma) * bloomSpread * (1.0 + bass * 2.0);
    inputColor += bloomAdd;

    // Merge through OkLab for smooth, hue-preserved phosphor trails.
    var state = mixOkLab(history, inputColor, 0.35 + bass * 0.15);
    state = max(state, history * 0.85);

    // Branchless CRT shadow mask and scan-line blanking.
    let mask = shadow_mask(pixel.x);
    state = mix(state, state * mask, shadowMaskStrength * (1.0 + mids * 0.6) * 0.5);

    let scanLine = sin(uv.y * res.y * 0.5 * (1.0 + rowVoice * 0.04)) * 0.5 + 0.5;
    state *= mix(1.0, scanLine, scanBlanking * (1.0 + treble * 0.4) * 0.4);

    let mDist = length((uv - smoothMouse) * vec2<f32>(aspect, 1.0));
    let mouseFalloff = 1.0 - smoothstep(0.0, 0.14, mDist);
    state += vec3<f32>(0.15, 0.35, 0.55) * mouseFalloff * (0.2 + treble * 0.3) * select(0.4, 1.0, held);

    var clickBloom = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 2.0) {
            let radius = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
            clickBloom = max(clickBloom, exp(-age * 2.5) * (1.0 - smoothstep(0.0, 0.12, radius)) + exp(-abs(radius - age * 0.1) * 60.0) * exp(-age * 1.1) * 0.6);
        }
    }
    state += vec3<f32>(1.0, 0.5 + rowVoice * 0.3, 0.25) * clickBloom * 0.5;

    // Depth haze + blackbody temperature grading.
    let depth = textureLoad(readDepthTexture, pixel, 0).r;
    let hazeColor = vec3<f32>(0.08, 0.06, 0.04) * 1.5;
    state = mixOkLab(state, hazeColor, depth * 0.25);

    let temp = 3200.0 + mids * 3000.0 + depth * 1500.0;
    state *= blackbodyRGB(temp);

    // Energy-carrying alpha for the feedback buffer.
    let energy = clamp(max(state.r, max(state.g, state.b)), 0.0, 1.0);
    textureStore(dataTextureA, pixel, vec4<f32>(state, energy));

    // ---- PASS 2: display output (tone-map, vignette, dither) ----
    state *= vignette(uv, 1.2);

    state = hue_preserve_clamp(state, 2.0);
    var finalRGB = aces_tone_map(state);
    finalRGB = to_srgb(finalRGB);

    // Semantic alpha = bloom/bright weight; IGN dither; premultiplied write.
    let luma = dot(finalRGB, vec3<f32>(0.2126, 0.7152, 0.0722));
    let bloomWeight = pow(max(0.0, luma - 0.55), 2.0) * 3.0;
    let alpha = clamp(bloomWeight + clickBloom * 0.25 + mouseFalloff * 0.1 + bass * 0.05, 0.0, 1.0);
    let dither = (ign(vec2<f32>(pixel)) - 0.5) / 255.0;
    finalRGB = finalRGB + vec3<f32>(dither);

    textureStore(writeTexture, pixel, vec4<f32>(finalRGB * alpha, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
